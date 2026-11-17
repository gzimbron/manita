import Foundation

/// A chiptune-style sound synthesized at runtime (no audio assets to license).
/// A square wave sweeps linearly from `startHz` to `endHz` with a linear fade-out.
public struct RetroSound: Equatable, Sendable {
    public var startHz: Double
    public var endHz: Double
    public var duration: TimeInterval

    public init(startHz: Double, endHz: Double, duration: TimeInterval) {
        self.startHz = startHz
        self.endHz = endHz
        self.duration = duration
    }

    /// Short descending "blip" played on mouse down.
    public static let click = RetroSound(startHz: 1_200, endHz: 600, duration: 0.05)

    /// Mono samples in `-volume...volume`.
    public func samples(sampleRate: Double, volume: Double) -> [Float] {
        let count = max(1, Int(duration * sampleRate))
        let amplitude = Float(min(max(volume, 0), 1))
        var phase = 0.0
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            let frequency = startHz + (endHz - startHz) * progress
            phase += frequency / sampleRate
            let square: Float = phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1
            return square * amplitude * Float(1 - progress)
        }
    }

    /// Encodes mono samples as a 16-bit PCM WAV file.
    public static func wavData(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1))                 // PCM
        append(UInt16(1))                 // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))    // byte rate
        append(UInt16(2))                 // block align
        append(UInt16(16))                // bits per sample
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
