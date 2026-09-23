import Foundation

actor PipedClient {
    // Piped keeps the client independent from YouTube's web UI. The endpoint can be
    // changed without rebuilding the app if an instance is unavailable.
    private let baseURL = URL(string: "https://pipedapi.kavin.rocks")!

    func search(_ query: String) async throws -> [Video] {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "filter", value: "music")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ClientError.server
        }
        return try JSONDecoder().decode(SearchResponse.self, from: data).items
            .filter { !$0.id.isEmpty && !$0.title.isEmpty }
    }

    func audioURL(for videoID: String) async throws -> URL {
        let url = baseURL.appendingPathComponent("streams").appendingPathComponent(videoID)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ClientError.server
        }
        let result = try JSONDecoder().decode(StreamResponse.self, from: data)
        guard let stream = result.audioStreams
            .filter({ URL(string: $0.url) != nil })
            .sorted(by: { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) })
            .first,
              let url = URL(string: stream.url) else {
            throw ClientError.noAudio
        }
        return url
    }

    enum ClientError: LocalizedError {
        case server, noAudio
        var errorDescription: String? {
            switch self {
            case .server: return "The music server is unavailable right now."
            case .noAudio: return "No playable audio stream was returned."
            }
        }
    }
}
