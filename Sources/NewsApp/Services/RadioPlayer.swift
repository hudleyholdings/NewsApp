import Foundation
import AVFoundation
import Combine

@MainActor
final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()

    @Published var currentStation: RadioStation?
    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var volume: Float = 0.8

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        // macOS doesn't need audio session setup like iOS
    }

    func play(_ station: RadioStation) {
        stop()
        currentStation = station
        isBuffering = true

        playerItem = AVPlayerItem(url: station.streamURL)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume

        // Observe player status
        playerItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isBuffering = false
                    self?.player?.play()
                    self?.isPlaying = true
                case .failed:
                    self?.isBuffering = false
                    self?.isPlaying = false
                    AppLogger.shared.log("RadioPlayer: Failed to load stream")
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Observe playback
        playerItem?.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLikely in
                if self?.player?.rate ?? 0 > 0 {
                    self?.isBuffering = !isLikely
                }
            }
            .store(in: &cancellables)
    }

    func togglePlayPause() {
        guard let player = player else { return }
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
        playerItem = nil
        currentStation = nil
        isPlaying = false
        isBuffering = false
        cancellables.removeAll()
    }

    func setVolume(_ newVolume: Float) {
        volume = newVolume
        player?.volume = newVolume
    }
}
