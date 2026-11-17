import Foundation
import Testing
@testable import ManitaCore

@Suite("ClickSound")
struct ClickSoundTests {
    private let rate = 44_100.0

    @Test func isShort() {
        let samples = ClickSound.samples(sampleRate: rate, volume: 0.6)
        let seconds = Double(samples.count) / rate
        #expect(seconds >= 0.02 && seconds <= 0.06)
    }

    @Test func peakNeverExceedsTheVolumeAndIsAudible() {
        for volume in [0.25, 0.6, 1.0] {
            let peak = ClickSound.samples(sampleRate: rate, volume: volume).map { abs($0) }.max() ?? 0
            #expect(Double(peak) <= volume + 1e-6)
            #expect(Double(peak) >= volume * 0.6)
        }
    }

    @Test func startsAndEndsNearSilence() {
        let volume = 0.8
        let samples = ClickSound.samples(sampleRate: rate, volume: volume)
        #expect(abs(Double(samples[0])) < volume * 0.02)
        #expect(abs(Double(samples[samples.count - 1])) < volume * 0.02)
    }

    @Test func isDeterministic() {
        #expect(ClickSound.samples(sampleRate: rate, volume: 0.5) == ClickSound.samples(sampleRate: rate, volume: 0.5))
    }

    @Test func isNotASquareBlip() {
        // A noise transient: many distinct sample values, energy concentrated at the start.
        let samples = ClickSound.samples(sampleRate: rate, volume: 1)
        #expect(Set(samples).count > samples.count / 2)
        let half = samples.count / 2
        let head = samples[..<half].reduce(0) { $0 + Double($1 * $1) }
        let tail = samples[half...].reduce(0) { $0 + Double($1 * $1) }
        #expect(head > tail * 4)
    }

    @Test func silentAtZeroVolumeAndClampsAboveOne() {
        #expect(ClickSound.samples(sampleRate: rate, volume: 0).allSatisfy { $0 == 0 })
        let loud = ClickSound.samples(sampleRate: rate, volume: 5).map { abs($0) }.max() ?? 0
        #expect(loud <= 1)
    }

    @Test func worksAtOtherSampleRates() {
        let samples = ClickSound.samples(sampleRate: 22_050, volume: 0.5)
        #expect(!samples.isEmpty)
        #expect(Double(samples.count) / 22_050 <= 0.06)
    }
}
