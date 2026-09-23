import Foundation

struct SearchResponse: Decodable {
    let items: [Video]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([Video].self) {
            items = array
        } else {
            let keyed = try container.decode(Keyed.self)
            items = keyed.items
        }
    }

    private struct Keyed: Decodable {
        let items: [Video]
    }
}

struct Video: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let uploaderName: String?
    let thumbnail: String?
    let duration: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, uploaderName, thumbnail, duration, url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(uploaderName, forKey: .uploaderName)
        try container.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try container.encodeIfPresent(duration, forKey: .duration)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decodeIfPresent(String.self, forKey: .id)
        let rawURL = try container.decodeIfPresent(String.self, forKey: .url)
        id = rawID ?? Self.videoID(from: rawURL ?? "") ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        uploaderName = try container.decodeIfPresent(String.self, forKey: .uploaderName)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
    }

    var subtitle: String {
        uploaderName ?? "YouTube Music"
    }

    var durationText: String {
        guard let duration, duration > 0 else { return "" }
        let m = duration / 60
        let s = duration % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func videoID(from url: String) -> String? {
        guard let components = URLComponents(string: url) else { return nil }
        if let value = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return value
        }
        let parts = components.path.split(separator: "/")
        return parts.last.map(String.init)
    }
}

struct StreamResponse: Decodable {
    let audioStreams: [AudioStream]
}

struct AudioStream: Decodable {
    let url: String
    let bitrate: Int?
    let format: String?
    let mimeType: String?
}
