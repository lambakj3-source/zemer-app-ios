import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var current: Video?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client = PipedClient()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var queue: [Video] = []
    private var queueIndex = 0

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        configureRemoteCommands()
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
    }

    func play(_ video: Video, queue: [Video] = []) {
        if !queue.isEmpty {
            self.queue = queue
            self.queueIndex = queue.firstIndex(of: video) ?? 0
        } else if self.queue.isEmpty {
            self.queue = [video]
            self.queueIndex = 0
        }
        load(video)
    }

    func next() {
        guard queueIndex + 1 < queue.count else { return }
        queueIndex += 1
        load(queue[queueIndex])
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if let player, player.currentTime().seconds > 5 {
            player.seek(to: .zero)
            return
        }
        guard queueIndex > 0 else {
            player?.seek(to: .zero)
            return
        }
        queueIndex -= 1
        load(queue[queueIndex])
    }

    private func load(_ video: Video) {
        current = video
        isLoading = true
        isPlaying = false
        errorMessage = nil
        Task {
            do {
                let url = try await client.audioURL(for: video.id)
                guard !Task.isCancelled else { return }
                let item = AVPlayerItem(url: url)
                player?.pause()
                player = AVPlayer(playerItem: item)
                if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
                if let timeObserver, let oldPlayer = player { oldPlayer.removeTimeObserver(timeObserver) }
                timeObserver = nil
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in Task { @MainActor in self?.next() } }
                player?.play()
                isPlaying = true
                isLoading = false
                if let player {
                    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.updateNowPlaying() }
                    }
                }
                updateNowPlaying()
            } catch {
                isLoading = false
                isPlaying = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        current = nil
        queue.removeAll()
        queueIndex = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.playCommand() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pauseCommand() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.player?.seek(to: CMTime(seconds: event.positionTime, preferredTimescale: 600))
            self?.updateNowPlaying()
            return .success
        }
    }

    private func playCommand() { player?.play(); isPlaying = true; updateNowPlaying() }
    private func pauseCommand() { player?.pause(); isPlaying = false; updateNowPlaying() }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.subtitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let duration = current.duration { info[MPMediaItemPropertyPlaybackDuration] = Double(duration) }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime().seconds ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
