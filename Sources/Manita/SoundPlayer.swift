import AVFoundation
import ManitaCore

/// Plays the synthesized click. A small round-robin pool lets fast
/// consecutive clicks overlap instead of cutting each other off.
@MainActor
final class SoundPlayer {
    private static let sampleRate = 44_100
    private var players: [AVAudioPlayer] = []
    private var next = 0

    var volume: Double = 0.6 {
        didSet { if volume != oldValue { players = [] } }
    }

    func playClick() {
        if players.isEmpty { buildPlayers() }
        guard !players.isEmpty else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.currentTime = 0
        player.play()
    }

    private func buildPlayers() {
        let samples = ClickSound.samples(sampleRate: Double(Self.sampleRate), volume: volume)
        let wav = RetroSound.wavData(samples: samples, sampleRate: Self.sampleRate)
        players = (0..<4).compactMap { _ in
            let player = try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
            player?.prepareToPlay()
            return player
        }
        next = 0
    }
}
