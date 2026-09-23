import Foundation

actor PipedClient: AudioResolving {
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

