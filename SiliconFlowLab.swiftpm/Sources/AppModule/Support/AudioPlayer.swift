import AVFoundation
import Foundation

/// 音声合成の結果を再生します。
@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?

    func load(_ data: Data) {
        stop()
        errorMessage = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        } catch {
            errorMessage = "音声を再生できませんでした: \(error.localizedDescription)"
            player = nil
        }
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        isPlaying = player.play()
    }

    func stop() {
        player?.stop()
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }
}
