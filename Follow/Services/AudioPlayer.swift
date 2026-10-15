import AVFoundation
import Observation

/// Plays a session's recording in its detail dialog: play/pause, a scrubber, and seeking from the transcript.
@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var isLoaded = false
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    func load(_ url: URL) {
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        currentTime = 0
        isLoaded = player != nil
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player, player.play() else { return }
        isPlaying = true
        // Follow the playhead while playing; AVAudioPlayer has no observable time.
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    return
                }
            }
        }
    }

    func pause() {
        player?.pause()
        ticker?.cancel()
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), duration)
        currentTime = player.currentTime
    }

    func stop() {
        pause()
        player?.stop()
    }
}
