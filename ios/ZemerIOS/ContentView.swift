import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var showNowPlaying = false

    var body: some View {
        TabView {
            SearchTab()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }

            LibraryTab()
                .tabItem {
                    Image(systemName: "music.note.list")
                    Text("Library")
                }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView().environmentObject(player)
        }
        .safeAreaInset(edge: .bottom) {
            if player.current != nil {
                Button { showNowPlaying = true } label: {
                    MiniPlayer().environmentObject(player)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SearchTab: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @State private var results: [Video] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchGeneration = UUID()
    private let client = PipedClient()

    var body: some View {
        NavigationView {
            Group {
                if results.isEmpty && query.isEmpty {
                    EmptyState()
                } else if isSearching {
                    ProgressView("Searching…")
                } else if results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 44))
                        Text("No results")
                            .font(.headline)
                        Text("Try another song or artist.")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List(results) { video in
                        Button {
                            player.play(video, queue: results)
                        } label: {
                            SongRow(video: video, isCurrent: player.current?.id == video.id)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                library.toggleFavorite(video)
                            } label: {
                                Label(
                                    library.isFavorite(video) ? "Remove" : "Save",
                                    systemImage: library.isFavorite(video) ? "star.slash" : "star"
                                )
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Zemer")
            .searchable(text: $query, prompt: "Songs, artists, albums")
            .onSubmit(of: .search) { search() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSearching { ProgressView() }
                }
            }
            .alert("Search", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        let generation = UUID()
        searchGeneration = generation

        Task {
            do {
                let newResults = try await client.search(text)
                guard generation == searchGeneration else { return }
                results = newResults
            } catch {
                guard generation == searchGeneration else { return }
                errorMessage = error.localizedDescription
            }
            guard generation == searchGeneration else { return }
            isSearching = false
        }
    }
}

private struct LibraryTab: View {
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationView {
            Group {
                if library.favorites.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "star")
                            .font(.system(size: 48))
                        Text("Your library is empty")
                            .font(.headline)
                        Text("Save songs from Search to keep them here.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List(library.favorites) { video in
                        Button {
                            player.play(video, queue: library.favorites)
                        } label: {
                            SongRow(video: video, isCurrent: player.current?.id == video.id)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                library.toggleFavorite(video)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Library")
        }
        .navigationViewStyle(.stack)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
            Text("Zemer")
                .font(.largeTitle.bold())
            Text("Search for music and play it in the background.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(32)
    }
}

private struct SongRow: View {
    let video: Video
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: video.thumbnail ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "music.note"))
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(video.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !video.durationText.isEmpty {
                    Text(video.durationText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isCurrent {
                Image(systemName: "waveform")
            }
        }
        .padding(.vertical, 4)
    }
}


private struct NowPlayingView: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(.presentationMode) private var presentationMode
    @State private var sliderValue = 0.0

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                AsyncImage(url: URL(string: player.current?.thumbnail ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.15))
                        .overlay(Image(systemName: "music.note").font(.system(size: 48)))
                }
                .frame(maxWidth: 320, maxHeight: 320)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 6) {
                    Text(player.current?.title ?? "")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(player.current?.subtitle ?? "")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { sliderValue },
                        set: { sliderValue = $0 }
                    ), in: 0...max(player.duration, 1), onEditingChanged: { editing in
                        if !editing { player.seek(to: sliderValue) }
                    })
                    HStack {
                        Text(timeText(player.elapsed))
                        Spacer()
                        Text(timeText(player.duration))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 42) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.title)
                    }
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 58))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.title)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Done") { presentationMode.wrappedValue.dismiss() })
            .onAppear { sliderValue = player.elapsed }
            .onReceive(player.$elapsed) { value in sliderValue = value }
        }
        .navigationViewStyle(.stack)
    }

    private func timeText(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MiniPlayer: View {
    @EnvironmentObject private var player: AudioPlayer

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(player.current?.subtitle ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if player.isLoading {
                ProgressView()
            } else {
                HStack(spacing: 14) {
                    Button {
                        player.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.toggle()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground))
    }
}

