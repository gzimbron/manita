# ADR 0007: Global shortcuts with Carbon `RegisterEventHotKey`

- Status: accepted
- Date: 2026-11-16

## Context

Showing or hiding the pointer and toggling presentation mode must work from any app, with the menu closed: `⌃⌥P` and `⌃⌥T` by default, changeable by the user. In presentation mode the shortcut is also the only way out, since clicks (including on the menu bar) are held back (ADR 0008), so it must keep working while Manita's own input handling is in play.

## Decision

- `HotkeyCenter` (`Sources/Manita/HotkeyCenter.swift`) registers each action's shortcut with Carbon `RegisterEventHotKey` on the application event target and installs one `kEventHotKeyPressed` handler. Hot key IDs carry the signature `'MnTa'`, so foreign IDs are ignored.
- A shortcut is a `Hotkey` value in `ManitaCore` (`Hotkey.swift`): the hardware virtual key code (layout independent, what the system matches on), a display label and modifiers. Defaults are `Hotkey.togglePointer` (`⌃⌥P`) and `Hotkey.presentationMode` (`⌃⌥T`). A valid shortcut needs a key and ⌃, ⌥ or ⌘; Shift alone would hijack typing.
- Both shortcuts are preferences. `Preferences.clamped()` replaces an invalid one with its default and, when both are equal, moves the presentation one aside.
- `register(_:)` replaces all registrations and returns the actions that failed (typically a shortcut another app already owns); failures are logged. `isRegistered(_:)` lets presentation mode check that its exit works before it starts.
- `ShortcutRecorder` captures a new shortcut from a key press in its own window; the hotkeys are unregistered while it is open so pressing the current shortcut records it instead of firing it.

## Alternatives considered

- **`NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`**: needs Accessibility (or Input Monitoring) permission, cannot consume the key press (the frontmost app still receives it), and does not see events delivered to Manita itself.
- **`CGEvent` tap on key events**: needs the same permission and puts every keystroke of the session through Manita, far more than two shortcuts need.
- **A third-party shortcut package**: wraps the same Carbon API; not worth a dependency for two shortcuts.

## Consequences

- No permission prompt: the shortcuts work system-wide as soon as the app runs, whichever app is frontmost.
- Carbon hot keys are exclusive: a combination another app has registered cannot be used, and the user must choose another one. Presentation mode refuses to start in that case.
- The API is old but still the standard way macOS apps register global shortcuts; if Apple removes it, `HotkeyCenter` is the only file to replace.
- With the menu open, one key press can arrive both as the menu item's key equivalent and as the hot key; `AppDelegate.toggle` ignores a second toggle of the same action within 0.3 s.
