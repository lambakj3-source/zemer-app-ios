import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [Video] = []

    private let key = "zemer.favorites"

    init() {
        load()
    }

    func isFavorite(_ video: Video) -> Bool {
        favorites.contains(where: { $0.id == video.id })
    }

    func toggleFavorite(_ video: Video) {
        if let index = favorites.firstIndex(where: { $0.id == video.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(video, at: 0)
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Video].self, from: data) else {
            return
        }
        favorites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
