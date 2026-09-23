import Foundation

/// Keeps stream resolution behind a small seam so the player does not depend
/// on a particular YouTube transport.
actor PlaybackResolver: AudioResolving {
    private let direct: InnerTubePlaybackResolver
    private let fallback: PipedClient

    init() {
        self.direct = InnerTubePlaybackResolver()
        self.fallback = PipedClient()
    }

    func audioURL(for videoID: String) async throws -> URL {
        do {
            return try await direct.audioURL(for: videoID)
        } catch {
            return try await fallback.audioURL(for: videoID)
        }
    }
}

private actor InnerTubePlaybackResolver {
    private let endpoint = URL(string: "https://music.youtube.com/youtubei/v1/player")!

    func audioURL(for videoID: String) async throws -> URL {
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20260213.01.00",
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20260213.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ResolverError.http
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streaming = root["streamingData"] as? [String: Any] else {
            throw ResolverError.noStream
        }

        let formats = (streaming["adaptiveFormats"] as? [[String: Any]] ?? [])
            + (streaming["formats"] as? [[String: Any]] ?? [])

        guard let best = formats.compactMap({ format -> (Int, URL)? in
            guard let mime = format["mimeType"] as? String,
                  mime.hasPrefix("audio/"),
                  let urlString = format["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            return (format["bitrate"] as? Int ?? 0, url)
        }).max(by: { $0.0 < $1.0 }) else {
            throw ResolverError.cipherRequired
        }

        return best.1
    }

    private enum ResolverError: Error {
        case http
        case noStream
        case cipherRequired
    }
}
