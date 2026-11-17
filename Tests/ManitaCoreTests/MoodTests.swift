import Foundation
import Testing
@testable import ManitaCore

@Suite("Mood")
struct MoodTests {
    @Test func hasFourLevelsAndStartsOnTheSecond() {
        #expect(Mood.range == 0...3)
        #expect(Preferences.default.mood == 1)
    }

    @Test func higherMoodMeansABolderLongerSleeve() {
        let styles = Mood.range.map(Mood.style)
        for (calm, loud) in zip(styles, styles.dropFirst()) {
            #expect(loud.armWidthScale > calm.armWidthScale)
            #expect(loud.armLengthInHands > calm.armLengthInHands)
            #expect(loud.armOpacity >= calm.armOpacity)
        }
    }

    @Test func higherMoodMeansAHarderClick() {
        let styles = Mood.range.map(Mood.style)
        for (calm, loud) in zip(styles, styles.dropFirst()) {
            #expect(loud.jabDistance > calm.jabDistance)
            #expect(loud.jabCount >= calm.jabCount)
            #expect(loud.burstRadius > calm.burstRadius)
            #expect(loud.burstRays > calm.burstRays)
            #expect(loud.trailCount >= calm.trailCount)
            #expect(loud.lingerDuration >= calm.lingerDuration)
        }
        #expect(styles[3].jabCount > styles[0].jabCount)
        #expect(styles[3].comicBursts)
    }

    @Test func outOfRangeLevelsUseTheNearestStyle() {
        #expect(Mood.style(-4) == Mood.style(0))
        #expect(Mood.style(99) == Mood.style(3))
        var prefs = Preferences.default
        prefs.mood = 12
        #expect(prefs.clamped().mood == 3)
        prefs.mood = -1
        #expect(prefs.clamped().mood == 0)
    }

    @Test func defaultHandIsLargerThanTheOldDefault() {
        #expect(Preferences.default.scale == 5)
        #expect(Preferences.scaleRange.contains(Preferences.default.scale))
    }

    @Test func automaticColorFollowsTheSystemAppearance() {
        #expect(Preferences.default.pointerColor == .automatic)
        #expect(PointerColor.automatic.resolved(systemIsDark: false) == RGBA(r: 0x11, g: 0x11, b: 0x11))
        #expect(PointerColor.automatic.resolved(systemIsDark: true) == PointerColor.white.resolved(systemIsDark: false))
        #expect(PointerColor.black.resolved(systemIsDark: true) == RGBA(r: 0x11, g: 0x11, b: 0x11))
        #expect(PointerColor.design.resolved(systemIsDark: true) == nil)
    }

    @Test func moodAndColorSurviveAStoreRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "manita.tests.mood.\(UUID().uuidString)"))
        let store = PreferencesStore(defaults: defaults)
        var prefs = Preferences.default
        prefs.mood = 3
        prefs.pointerColor = .white
        store.save(prefs)
        #expect(store.load().mood == 3)
        #expect(store.load().pointerColor == .white)
    }
}
