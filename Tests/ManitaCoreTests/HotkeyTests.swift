import Foundation
import Testing
@testable import ManitaCore

@Suite("Hotkeys")
struct HotkeyTests {
    @Test func defaultsMatchTheReferenceShortcuts() {
        #expect(Hotkey.togglePointer.display == "⌃⌥P")
        #expect(Hotkey.presentationMode.display == "⌃⌥T")
        // ANSI virtual key codes for P and T: what the system actually matches on.
        #expect(Hotkey.togglePointer.keyCode == 35)
        #expect(Hotkey.presentationMode.keyCode == 17)
        #expect(Preferences.default.pointerHotkey == .togglePointer)
        #expect(Preferences.default.presentationHotkey == .presentationMode)
    }

    @Test func displayListsModifiersInSystemOrder() {
        let hotkey = Hotkey(keyCode: 40, key: "k", modifiers: [.command, .shift, .option, .control])
        #expect(hotkey.display == "⌃⌥⇧⌘K")
    }

    @Test func requiresAKeyAndANonShiftModifier() {
        #expect(Hotkey(keyCode: 35, key: "P", modifiers: [.control]).isValid)
        #expect(Hotkey(keyCode: 35, key: "P", modifiers: [.command, .shift]).isValid)
        #expect(!Hotkey(keyCode: 35, key: "P", modifiers: []).isValid)
        #expect(!Hotkey(keyCode: 35, key: "P", modifiers: [.shift]).isValid)
        #expect(!Hotkey(keyCode: 35, key: "", modifiers: [.control]).isValid)
    }

    @Test func customHotkeysSurviveAStoreRoundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "manita.tests.hotkeys.\(UUID().uuidString)"))
        let store = PreferencesStore(defaults: defaults)
        var prefs = Preferences.default
        prefs.pointerHotkey = Hotkey(keyCode: 46, key: "M", modifiers: [.command, .shift])
        store.save(prefs)
        #expect(store.load().pointerHotkey == Hotkey(keyCode: 46, key: "M", modifiers: [.command, .shift]))
        #expect(store.load().presentationHotkey == .presentationMode)
    }

    @Test func clampingRepairsInvalidAndConflictingHotkeys() {
        var prefs = Preferences.default
        prefs.pointerHotkey = Hotkey(keyCode: 35, key: "P", modifiers: [])
        #expect(prefs.clamped().pointerHotkey == .togglePointer)

        // Both actions on one shortcut: the presentation shortcut gives way.
        prefs = .default
        prefs.pointerHotkey = Hotkey(keyCode: 46, key: "M", modifiers: [.control])
        prefs.presentationHotkey = prefs.pointerHotkey
        #expect(prefs.clamped().pointerHotkey == Hotkey(keyCode: 46, key: "M", modifiers: [.control]))
        #expect(prefs.clamped().presentationHotkey == .presentationMode)

        // …unless the pointer shortcut took the presentation default.
        prefs.pointerHotkey = .presentationMode
        prefs.presentationHotkey = .presentationMode
        #expect(prefs.clamped().presentationHotkey == .togglePointer)
    }

    @Test func conflictsAreDecidedByThePhysicalKeyNotItsLabel() {
        // The same physical key reads "L" on Dvorak: still the same system shortcut.
        let relabeled = Hotkey(keyCode: 35, key: "L", modifiers: [.control, .option])
        #expect(relabeled.conflicts(with: .togglePointer))
        #expect(!Hotkey.presentationMode.conflicts(with: .togglePointer))
        #expect(!Hotkey(keyCode: 35, key: "P", modifiers: [.command]).conflicts(with: .togglePointer))

        var prefs = Preferences.default
        prefs.presentationHotkey = relabeled
        #expect(prefs.clamped().presentationHotkey == .presentationMode)
    }

    @Test func preferencesSavedBeforeHotkeysExistedKeepTheirValues() throws {
        let old = #"{"isEnabled":false,"soundEnabled":false,"clickAnimationEnabled":true,"volume":0.25,"scale":2,"skinID":"pocket","hideSystemCursor":false,"showArm":false}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
        #expect(!prefs.isEnabled)
        #expect(prefs.skinID == "pocket")
        #expect(prefs.volume == 0.25)
        #expect(prefs.pointerHotkey == .togglePointer)
    }
}
