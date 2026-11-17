import Foundation
import Testing
@testable import ManitaCore

@Suite("Effects threshold")
struct EffectsThresholdTests {
    @Test func defaultsToTheThirdRapidClick() {
        #expect(Preferences.default.effectsFromClick == 3)
        #expect(Preferences.effectsFromClickRange == 1...10)
    }

    @Test func effectsStartAtTheConfiguredClick() {
        var streak = ClickStreak()
        let threshold = 4
        var plays: [Bool] = []
        for i in 0..<5 {
            streak.press(at: Double(i) * 0.1)
            plays.append(streak.playsEffects(from: threshold))
        }
        #expect(plays == [false, false, false, true, true])
    }

    @Test func fromTheFirstClickEveryPressPlays() {
        var streak = ClickStreak()
        streak.press(at: 0)
        #expect(streak.playsEffects(from: 1))
    }

    @Test func outOfRangeValuesAreClamped() {
        var prefs = Preferences.default
        prefs.effectsFromClick = 0
        #expect(prefs.clamped().effectsFromClick == 1)
        prefs.effectsFromClick = 50
        #expect(prefs.clamped().effectsFromClick == 10)
    }

    @Test func survivesAStoreRoundTripAndOldDataGetsTheDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "manita.tests.threshold.\(UUID().uuidString)"))
        let store = PreferencesStore(defaults: defaults)
        var prefs = Preferences.default
        prefs.effectsFromClick = 5
        store.save(prefs)
        #expect(store.load().effectsFromClick == 5)

        let old = #"{"isEnabled":true,"soundEnabled":true,"clickAnimationEnabled":true,"volume":0.5,"scale":5,"skinID":"cartoon","hideSystemCursor":true,"showArm":true}"#
        #expect(try JSONDecoder().decode(Preferences.self, from: Data(old.utf8)).effectsFromClick == 3)
    }
}
