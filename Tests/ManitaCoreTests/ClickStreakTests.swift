import Foundation
import Testing
@testable import ManitaCore

@Suite("ClickStreak")
struct ClickStreakTests {
    @Test func startsEmpty() {
        let streak = ClickStreak()
        #expect(streak.count == 0)
        #expect(!streak.playsEffects)
        #expect(streak.intensity == 0)
    }

    @Test func rapidPressesExtendTheStreak() {
        var streak = ClickStreak()
        #expect(streak.press(at: 10) == 1)
        #expect(streak.press(at: 10.3) == 2)
        #expect(streak.press(at: 10.6) == 3)
        #expect(streak.count == 3)
    }

    @Test func aSlowPressRestartsAtOne() {
        var streak = ClickStreak()
        _ = streak.press(at: 10)
        _ = streak.press(at: 10.2)
        #expect(streak.press(at: 10.2 + 0.46) == 1)
        #expect(streak.count == 1)
    }

    @Test func theGapIsMeasuredFromThePreviousPressNotTheFirst() {
        var streak = ClickStreak()
        var time = 100.0
        for expected in 1...8 {
            #expect(streak.press(at: time) == expected)
            time += 0.4
        }
    }

    @Test func effectsStartOnTheThirdPress() {
        var streak = ClickStreak()
        _ = streak.press(at: 0)
        #expect(!streak.playsEffects)
        _ = streak.press(at: 0.2)
        #expect(!streak.playsEffects)
        _ = streak.press(at: 0.4)
        #expect(streak.playsEffects)
        _ = streak.press(at: 0.6)
        #expect(streak.playsEffects)
    }

    @Test func aRestartedStreakStopsTheEffects() {
        var streak = ClickStreak()
        for t in [0, 0.2, 0.4, 0.6] { _ = streak.press(at: t) }
        #expect(streak.playsEffects)
        _ = streak.press(at: 5)
        #expect(!streak.playsEffects)
        #expect(streak.intensity == 0)
    }

    @Test func intensityIsNormalOnThirdPressThenGrowsAndIsCapped() {
        var streak = ClickStreak()
        var seen: [Double] = []
        var time = 0.0
        for _ in 1...30 {
            _ = streak.press(at: time)
            time += 0.2
            seen.append(streak.intensity)
        }
        #expect(seen[0] == 0 && seen[1] == 0)
        #expect(seen[2] == 1)
        #expect(seen[3] > seen[2])
        #expect(zip(seen.dropFirst(2), seen.dropFirst(3)).allSatisfy { $0 <= $1 })
        #expect(seen.max() == ClickStreak.maxIntensity)
        #expect(seen.last == ClickStreak.maxIntensity)
        #expect(ClickStreak.maxIntensity > 1 && ClickStreak.maxIntensity <= 1.5)
    }

    @Test func aClockGoingBackwardsRestartsTheStreak() {
        var streak = ClickStreak()
        _ = streak.press(at: 50)
        _ = streak.press(at: 50.1)
        #expect(streak.press(at: 20) == 1)
    }

    @Test func windowIsAboutHalfASecond() {
        #expect(ClickStreak.window == 0.45)
        #expect(ClickStreak.effectThreshold == 3)
    }
}
