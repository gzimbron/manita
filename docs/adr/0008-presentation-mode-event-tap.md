# ADR 0008: Presentation mode with a session event tap

- Status: accepted
- Date: 2026-11-16
- Amends: the "Manita can never swallow or alter a click" consequence of [ADR 0001](0001-overlay-window.md), for presentation mode only

## Context

When presenting, people point at things and click for emphasis, and each click advances the slide or presses whatever is under the pointer. Presentation mode must let the hand animate on every click while no app receives it. The event monitors of ADR 0001 can only observe, so they cannot do this.

## Decision

- `ClickDisarmer` (`Sources/Manita/ClickDisarmer.swift`) installs an active `CGEvent` tap at `.cgSessionEventTap`, `.headInsertEventTap`, on the main run loop, for left, right and other mouse buttons:
  - presses and releases are dropped (`nil`) and reported through `onButton`, after the callback returns, to `AppDelegate.handleButton`, so the jab, burst and sound still play;
  - drags are rewritten to `.mouseMoved`, so no app sees a drag without its mouse-down and the pointer keeps following the mouse;
  - scrolling and keys are not tapped and pass through untouched;
  - if macOS disables the tap (timeout or user input), it is re-enabled while it is still meant to be running.
- Creating an active tap needs **Accessibility** permission. `AppDelegate.startPresentation()` checks it with `AXIsProcessTrustedWithOptions` (no prompt); when it is missing or the tap cannot be created, an alert offers to open *System Settings › Privacy & Security › Accessibility*.
- Safety rules, because the tap also blocks clicks on the menu bar and on Manita's own menu:
  - **Refuses to start without its exit**: presentation mode starts only when its shortcut is registered (`HotkeyCenter.isRegistered(.togglePresentation)`, ADR 0007); otherwise an alert asks for a different one. If the shortcut stops being registered while active, `apply()` leaves presentation mode.
  - **Hiding the pointer exits**: clicks are never disarmed without a visible pointer; `apply()` stops presentation mode when Manita is disabled, and starting it shows the pointer if it was hidden.
  - **Never persisted**: the state lives only in `ClickDisarmer.isActive`, not in `Preferences`, so every launch starts with working clicks. The tap is removed in `applicationWillTerminate` and when `ClickDisarmer` is released.
- `PresentationNotice` shows the exit shortcut with a progress bar on entry, and a short notice on exit.

## Consequences

- Manita can now block input. That is limited to mouse buttons while presentation mode is on, and always paired with a registered exit shortcut.
- The shortcut is the only way out while active (besides the pointer shortcut); a crash or force-kill also removes the tap, because it dies with the process.
- Accessibility permission is tied to the code signature. `scripts/build-app.sh` signs with an Apple Development certificate when one exists, so the permission survives rebuilds; an ad-hoc build (no certificate) loses it on every rebuild.
- Every mouse button event in the session passes through the callback on the main thread; it must stay short so macOS does not time the tap out.
