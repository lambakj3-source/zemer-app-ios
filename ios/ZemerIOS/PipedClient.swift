import Foundation

actor PipedClient: AudioResolving {
    private let direct = InnerTubeClient()
    private let baseURLs: [URL] = [
        URL(string: "https://pipedapi.kavin.rocks")!,
        URL(string: "https://pipedapi.leptons.xyz")!,
        URL(string: "https://pipedapi.nosebs.ru")!,
        URL(string: "https://api.piped.yt")!
    ]

    func search(_ query: String) async throws -> [Video] {
        var lastError: Error = ClientError.server
        for baseURL in baseURLs {
            do {
                var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "filter", value: "music")
                ]
                var request = URLRequest(url: components.url!)
                request.timeoutInterval = 12
                request.setValue("Zemer-iOS/0.1", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw ClientError.server
                }
                let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
                let results = decoded.items.filter { !$0.id.isEmpty && !$0.title.isEmpty }
                if !results.isEmpty { return results }
                lastError = ClientError.noResults
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func audioURL(for videoID: String) async throws -> URL {
        // Try Zemer-compatible InnerTube playback first. The direct client only
        // accepts a stream when YouTube gives us a complete, already-playable URL.
        // Ciphered URLs are deliberately rejected here and fall through to Piped
        // until the Swift cipher/poToken layer is ported.
        if let url = try? await direct.audioURL(for: videoID) {
            return url
        }

        var lastError: Error = ClientError.server
        for baseURL in baseURLs {
            do {
                let url = baseURL.appendingPathComponent("streams").appendingPathComponent(videoID)
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.setValue("Zemer-iOS/0.1", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw ClientError.server
                }
                let result = try JSONDecoder().decode(StreamResponse.self, from: data)
                guard let stream = result.audioStreams
                    .filter({ URL(string: $0.url) != nil })
                    .sorted(by: { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) })
                    .first,
                    let streamURL = URL(string: stream.url) else {
                    throw ClientError.noAudio
                }
                return streamURL
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    enum ClientError: LocalizedError {
        case server, noAudio, noResults
        var errorDescription: String? {
            switch self {
            case .server: return "The music servers are unavailable right now."
            case .noAudio: return "No playable audio stream was returned."
            case .noResults: return "No music results were returned."
            }
        }
    }
}

private actor InnerTubeClient {
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
        let data = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20260213.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0", forHTTPHeaderField: "User-Agent")

        let (dataResponse, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw DirectError.http
        }
        guard let root = try JSONSerialization.jsonObject(with: dataResponse) as? [String: Any] else {
            throw DirectError.invalidResponse
        }

        if let playability = root["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            let reason = playability["reason"] as? String
            throw DirectError.playability(reason ?? status)
        }

        guard let streaming = root["streamingData"] as? [String: Any] else {
            throw DirectError.noStream
        }

        // YouTube may put playable audio in either adaptiveFormats or formats.
        // URLs protected by signatureCipher are intentionally left for the
        // future Swift cipher layer rather than pretending they are playable.
        let adaptive = streaming["adaptiveFormats"] as? [[String: Any]] ?? []
        let progressive = streaming["formats"] as? [[String: Any]] ?? []
        let formats = adaptive + progressive

        let audio = formats.compactMap { format -> (Int, URL)? in
            guard let mime = format["mimeType"] as? String, mime.hasPrefix("audio/") else {
                return nil
            }
            guard let urlString = format["url"] as? String,
                  let url = URL(string: urlString) else {
                return nil
            }
            return (format["bitrate"] as? Int ?? 0, url)
        }.max(by: { $0.0 < $1.0 })

        guard let audio else {
            if formats.contains(where: { $0["signatureCipher"] != nil || $0["cipher"] != nil }) {
                throw DirectError.cipherRequired
            }
            throw DirectError.noAudio
        }
        return audio.1
    }

    private enum DirectError: LocalizedError {
        case http
        case invalidResponse
        case noStream
        case noAudio
        case cipherRequired
        case playability(String)

        var errorDescription: String? {
            switch self {
            case .http:
                return "YouTube did not return a successful playback response."
            case .invalidResponse:
                return "YouTube returned an invalid playback response."
            case .noStream:
                return "YouTube did not return streaming data."
            case .noAudio:
                return "YouTube returned no directly playable audio stream."
            case .cipherRequired:
                return "This stream requires signature decoding."
            case .playability(let reason):
                return "YouTube playback is unavailable: \(reason)"
            }
        }
    }
}
