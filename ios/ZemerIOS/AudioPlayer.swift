import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

protocol AudioResolving {
    func audioURL(for videoID: String) async throws -> URL
}

final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var current: Video?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var errorMessage: String?

    private let client: AudioResolving

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var queue: [Video] = []
    private var queueIndex = 0
    private var loadToken = UUID()
    private var interruptionObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var artworkCache: [String: MPMediaItemArtwork] = [:]

    override init() {
        self.client = PlaybackResolver()
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        configureRemoteCommands()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in self?.handleInterruption(notification) }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
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
        loadToken = UUID()
        let token = loadToken
        current = video
        elapsed = 0
        duration = Double(video.duration ?? 0)
        isLoading = true
        isPlaying = false
        errorMessage = nil
        Task {
            do {
                let url = try await client.audioURL(for: video.id)
                guard !Task.isCancelled, token == loadToken else { return }
                let item = AVPlayerItem(url: url)
                player?.pause()
                if let timeObserver, let oldPlayer = player { oldPlayer.removeTimeObserver(timeObserver) }
                timeObserver = nil
                player = AVPlayer(playerItem: item)
                if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
                if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
                itemFailureObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] notification in
                    Task { @MainActor in
                        guard let self, token == self.loadToken else { return }
                        self.isLoading = false
                        self.isPlaying = false
                        self.errorMessage = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "This track could not be played."
                        self.updateNowPlaying()
                    }
                }
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in Task { @MainActor in self?.next() } }
                player?.play()
                isPlaying = true
                isLoading = false
                if let player {
                    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
                        Task { @MainActor in
                            guard let self else { return }
                            self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                            if let itemDuration = self.player?.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                                self.duration = itemDuration
                            }
                            self.updateNowPlaying()
                        }
                    }
                }
                updateNowPlaying()
                loadArtwork(for: video, token: token)
            } catch {
                isLoading = false
                isPlaying = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func seek(to seconds: Double) {
        guard let player, seconds.isFinite else { return }
        let target = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        elapsed = target
        updateNowPlaying()
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func stop() {
        player?.pause()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
        itemFailureObserver = nil
        player = nil
        isPlaying = false
        elapsed = 0
        duration = 0
        current = nil
        queue.removeAll()
        queueIndex = 0
        loadToken = UUID()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteCommandState()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            isPlaying = false
            updateNowPlaying()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume),
               current != nil {
                try? AVAudioSession.sharedInstance().setActive(true)
                player?.play()
                isPlaying = true
                updateNowPlaying()
            }
        @unknown default:
            break
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.changePlaybackPositionCommand.isEnabled = false
        center.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.playCommand() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pauseCommand() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func playCommand() { player?.play(); isPlaying = true; updateNowPlaying() }
    private func pauseCommand() { player?.pause(); isPlaying = false; updateNowPlaying() }

    private func updateRemoteCommandState() {
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = queueIndex + 1 < queue.count
        center.previousTrackCommand.isEnabled = !queue.isEmpty
        center.changePlaybackPositionCommand.isEnabled = player != nil
    }

    private func loadArtwork(for video: Video, token: UUID) {
        guard let thumbnail = video.thumbnail, let url = URL(string: thumbnail) else { return }
        if let artwork = artworkCache[video.id] {
            updateNowPlaying(artwork: artwork)
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard token == loadToken, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                artworkCache[video.id] = artwork
                updateNowPlaying(artwork: artwork)
            } catch {
            }
        }
    }

    private func updateNowPlaying(artwork: MPMediaItemArtwork? = nil) {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyArtist: current.subtitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let duration = current.duration { info[MPMediaItemPropertyPlaybackDuration] = Double(duration) }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        else if let cached = artworkCache[current.id] { info[MPMediaItemPropertyArtwork] = cached }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
