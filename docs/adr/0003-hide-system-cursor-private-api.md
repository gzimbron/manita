# ADR 0003: Hide the system pointer with a guarded private API

- Status: superseded by [ADR 0005](0005-replace-system-cursors.md) (this mechanism remains as the fallback)
- Date: 2026-11-16

## Context

With the overlay (ADR 0001), the macOS arrow is still drawn under the hand. `CGDisplayHideCursor` only hides it while our app is frontmost, and a menu bar app almost never is.

## Decision

Set the private connection property `SetsCursorInBackground` via `CGSSetConnectionProperty`, which lets `CGDisplayHideCursor` apply while in the background. Both symbols are resolved with `dlsym` at runtime; if they are missing or the call fails, Manita leaves the pointer visible. The feature is a user toggle (**Hide System Pointer**) and the pointer is always restored on quit or disable.

## Consequences

- Private API: incompatible with the Mac App Store and may break in a future macOS. Failure mode is cosmetic (arrow visible).
- Distribution must be direct download (e.g. GitHub Releases, notarized).
- Revisit if Apple ships a public API for this.
