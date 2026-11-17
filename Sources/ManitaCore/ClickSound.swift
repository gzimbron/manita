import Foundation

/// A short, natural mouse-click sound synthesized at runtime (no audio assets):
/// a filtered-noise transient with a very fast attack and exponential decay, plus a
/// faint high resonant tick. Deterministic: the noise comes from a fixed-seed generator.
public enum ClickSound {
    /// Total length in seconds.
    public static let duration: TimeInterval = 0.03

    /// Mono samples in `-volume...volume`.
    public static func samples(sampleRate: Double, volume: Double) -> [Float] {
        let count = max(1, Int(duration * sampleRate))
        let amplitude = min(max(volume, 0), 1)
        guard amplitude > 0 else { return [Float](repeating: 0, count: count) }

        var generator = SeededNoise(seed: 0x4D41_4E49_5441)
        let attack = 0.0004          // seconds to reach full level
        let decay = 0.0045           // noise decay time constant
        let tickDecay = 0.0016
        let tickHz = 3_300.0
        let release = 0.003          // closing fade, so the clip ends at silence

        // Band-limit the noise: low-pass minus a slower low-pass leaves a mid band without a DC offset.
        var fast = 0.0, slow = 0.0
        var raw = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            let noise = generator.next()
            fast += 0.42 * (noise - fast)
            slow += 0.05 * (noise - slow)
            let body = (fast - slow) * exp(-t / decay)
            let tick = sin(2 * .pi * tickHz * t) * exp(-t / tickDecay) * 0.22
            let rise = min(1, t / attack)
            let tailLeft = Double(count - 1 - index) / sampleRate
            let fall = min(1, tailLeft / release)
            raw[index] = (body + tick) * rise * fall
        }
        let peak = raw.map { abs($0) }.max() ?? 1
        let gain = peak > 0 ? amplitude / peak : 0
        return raw.map { Float($0 * gain) }
    }
}

/// Small deterministic noise source (SplitMix64), values in `-1...1`.
private struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53) * 2 - 1
    }
}
