import Foundation

/// A parsed InnerTube playback format. Keeping the raw cipher fields lets the
/// resolver add signature/n transformation without changing the network layer.
struct PlaybackFormat: Sendable {
    let itag: Int
    let mimeType: String
    let bitrate: Int
    let directURL: URL?
    let signatureCipher: String?
    let contentLength: Int64?

    var needsCipher: Bool {
        directURL == nil && signatureCipher != nil
    }
}

/// Small, transport-independent representation of the playback response.
struct PlaybackResponse: Sendable {
    let formats: [PlaybackFormat]
    let playabilityStatus: String?
    let playabilityReason: String?
    let serverABRStreamingURL: URL?

    static func parse(_ data: Data) throws -> PlaybackResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        let playability = root["playabilityStatus"] as? [String: Any]
        let status = playability?["status"] as? String
        let reason = playability?["reason"] as? String

        let streaming = root["streamingData"] as? [String: Any]
        let adaptive = streaming?["adaptiveFormats"] as? [[String: Any]] ?? []
        let progressive = streaming?["formats"] as? [[String: Any]] ?? []

        let formats = (adaptive + progressive).compactMap { item -> PlaybackFormat? in
            guard let mime = item["mimeType"] as? String else { return nil }
            let itag = item["itag"] as? Int ?? 0
            let bitrate = item["bitrate"] as? Int ?? 0
            let length = (item["contentLength"] as? String).flatMap(Int64.init)
                ?? (item["contentLength"] as? Int).map(Int64.init)

            let directURL = (item["url"] as? String).flatMap(URL.init(string:))
            let cipher = (item["signatureCipher"] as? String)
                ?? (item["cipher"] as? String)

            guard directURL != nil || cipher != nil else { return nil }
            return PlaybackFormat(
                itag: itag,
                mimeType: mime,
                bitrate: bitrate,
                directURL: directURL,
                signatureCipher: cipher,
                contentLength: length
            )
        }

        let abr = (streaming?["serverAbrStreamingUrl"] as? String).flatMap(URL.init(string:))

        return PlaybackResponse(
            formats: formats,
            playabilityStatus: status,
            playabilityReason: reason,
            serverABRStreamingURL: abr
        )
    }

    enum ParseError: Error {
        case invalidJSON
    }
}
