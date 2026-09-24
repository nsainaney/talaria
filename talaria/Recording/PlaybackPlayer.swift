import AVFoundation
import Foundation
import Observation

/// Plays one kept recording at a time, for the recordings list.
@Observable @MainActor
final class PlaybackPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = PlaybackPlayer()

    private(set) var playingName: String?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var error: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Play this file, pause if it is already playing, or resume if it is paused.
    func toggle(_ url: URL) {
        let name = url.lastPathComponent
        if playingName == name, let player {
            if player.isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true }
            return
        }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            playingName = name
            duration = p.duration
            position = 0
            error = nil
            p.play()
            isPlaying = true
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, let player = self.player else { return }
                    self.position = player.currentTime
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Jump by a number of seconds within the file that is playing (or paused).
    func skip(_ seconds: TimeInterval, in url: URL) {
        guard playingName == url.lastPathComponent, let player else { return }
        player.currentTime = max(0, min(player.duration, player.currentTime + seconds))
        position = player.currentTime
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(player.duration, fraction * player.duration))
        position = player.currentTime
    }

    func stop() {
        ticker?.cancel()
        player?.stop()
        player = nil
        playingName = nil
        isPlaying = false
        position = 0
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in PlaybackPlayer.shared.stop() }
    }
}
