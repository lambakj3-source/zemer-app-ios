import Foundation

struct SearchResponse: Decodable {
    let items: [Video]
}

struct Video: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let uploaderName: String?
    let thumbnail: String?
    let duration: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, uploaderName, thumbnail, duration
    }

    var subtitle: String {
        uploaderName ?? "YouTube Music"
    }

    var durationText: String {
        guard let duration else { return "" }
        let m = duration / 60
        let s = duration % 60
        return String(format: "%d:%02d", m, s)
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
