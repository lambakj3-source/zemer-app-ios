import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var player: AudioPlayer
    @State private var query = ""
    @State private var results: [Video] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    private let client = PipedClient()

    var body: some View {
        NavigationStack {
            Group {
                if results.isEmpty && query.isEmpty {
                    EmptyState()
                } else if isSearching {
                    ProgressView("Searching…")
                } else if results.isEmpty {
                    ContentUnavailableView("No results", systemImage: "music.note", description: Text("Try another song or artist."))
                } else {
                    List(results) { video in
                        Button {
                            player.play(video)
                        } label: {
                            SongRow(video: video, isCurrent: player.current?.id == video.id)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Zemer")
            .searchable(text: $query, prompt: "Songs, artists, albums")
            .onSubmit(of: .search) { search() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isSearching { ProgressView() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if player.current != nil {
                    MiniPlayer()
                        .environmentObject(player)
                }
            }
            .alert("Playback", isPresented: Binding(
                get: { player.errorMessage != nil },
                set: { if !$0 { player.errorMessage = nil } }
            )) {
                Button("OK") { player.errorMessage = nil }
            } message: {
                Text(player.errorMessage ?? "")
            }
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                results = try await client.search(text)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
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
                .foregroundStyle(.secondary)
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
                Rectangle().fill(.secondary.opacity(0.15))
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !video.durationText.isEmpty {
                    Text(video.durationText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if player.isLoading {
                ProgressView()
            } else {
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
