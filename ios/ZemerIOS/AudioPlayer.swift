import Foundation
import AVFoundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var current: Video?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client = PipedClient()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func play(_ video: Video) {
        current = video
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let url = try await client.audioURL(for: video.id)
                guard !Task.isCancelled else { return }
                let item = AVPlayerItem(url: url)
                player?.pause()
                player = AVPlayer(playerItem: item)
                if let endObserver {
                    NotificationCenter.default.removeObserver(endObserver)
                }
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    self?.isPlaying = false
                }
                player?.play()
                isPlaying = true
                isLoading = false
            } catch {
                isLoading = false
                isPlaying = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        current = nil
    }
}
