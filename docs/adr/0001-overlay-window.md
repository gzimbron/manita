# ADR 0001: Draw the hand in a floating overlay window

- Status: accepted
- Date: 2026-11-16

## Context

Manita must show a custom hand wherever the pointer is, in every app. `NSCursor` only applies while the pointer is over the app's own windows; macOS offers no public API to replace the cursor system-wide.

## Decision

Draw the hand in a small borderless, transparent `NSPanel` that:

- ignores mouse events (clicks pass through to the app below),
- sits at `.screenSaver` level and joins all Spaces and full-screen apps,
- is repositioned on every mouse event from global and local `NSEvent` monitors.

The skin's hotspot is kept at the panel's center so click effects are centered on the real click point.

## Consequences

- Works system-wide with full Core Animation effects.
- The real pointer is still drawn by macOS; hiding it needs ADR 0003.
- Pointer tracking depends on event monitors, which macOS may gate behind privacy permissions.
- Event monitors only observe; outside presentation mode Manita never swallows or alters a click
  (presentation mode holds clicks back on purpose, see [ADR 0008](0008-presentation-mode-event-tap.md)).

Update (1.0.0): the overlay is no longer one small panel centered on the hotspot. `OverlayController` owns one static, full-frame, click-through panel per display (`PointerSurface`) and moves only the pointer layers inside it, so the hand and sleeve are drawn in parts across displays. The click-through, `.screenSaver` level, all-Spaces and event-monitor decisions above still hold. See [ARCHITECTURE.md](../ARCHITECTURE.md).
