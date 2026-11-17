# ADR 0005: Replace system cursors with a transparent image

- Status: accepted
- Date: 2026-11-16
- Supersedes the mechanism of [ADR 0003](0003-hide-system-cursor-private-api.md) (kept as the fallback)

## Context

ADR 0003 hid the pointer with `CGDisplayHideCursor`. macOS re-shows it whenever another app sets a cursor (for example the pointing-hand link cursor in a browser), so the real pointer reappeared on top of the glove.

## Decision

Register a fully transparent cursor under every system cursor name, the technique used by [Mousecape](https://github.com/alexzielenski/Mousecape). Sources (all in `Mousecape/mousecloak/`):

- `CGSInternal/CGSCursor.h`: `CGSRegisterCursorWithImages(cid, char *name, bool setGlobally, bool instantly, CGSize size, CGPoint hotspot, NSUInteger frameCount, CGFloat frameDuration, CFArrayRef images, int *seed)`, `CoreCursorUnregisterAll(cid)`, `CoreCursorSet(cid, id)`.
- `CGSInternal/CGSConnection.h`: `CGSMainConnectionID()`.
- `apply.m` (`applyCursorForIdentifier`): calls the register function with `setGlobally = true, instantly = true`.
- `restore.m` (`resetAllCursors`): `CoreCursorUnregisterAll`, then `CoreCursorSet` for ids 0..<45.
- `MCDefs.m`: `defaultCursors` (`com.apple.coregraphics.Arrow`, `IBeam`, `IBeamXOR`, `Alias`, `Copy`, `Move`, `ArrowCtx`, `Wait`, `Empty`) and `cursorMap()` (`com.apple.cursor.2…43`, e.g. `.2` Link, `.13` Pointing).

Implementation:

- Pure data (name list, 16 pt / 2x all-zero image spec, fallback policy) is in `ManitaCore/CursorOverride.swift` and tested.
- `Sources/Manita/SystemCursorHider.swift` resolves the four symbols with `dlsym` (no private linking), registers the image for every name, and restores with Mousecape's reset sequence.
- Fallback chain: transparent cursors → ADR 0003 hide (`CGDisplayHideCursor` + `SetsCursorInBackground`) → pointer left visible. Any missing symbol, or failure to replace the Arrow, triggers the next step. The chosen mode is logged (`Manita: system pointer mode = …`).
- `reassert()` re-registers at most once per second in case macOS reset the cursors.
- Restore happens on disable, in `applicationWillTerminate`, via `atexit`, and on SIGTERM/SIGINT/SIGHUP (handled on a global queue so a busy main thread does not block it).

## Consequences

- Private API, direct download only; may break in a future macOS (failure is cosmetic, handled by the fallback).
- Cursors are replaced system-wide while Manita runs. After a crash or SIGKILL nothing can restore them: the user recovers by relaunching Manita and quitting it (or turning the setting off), or by logging out.
- Cursor images are not readable by the user while overridden; screenshots show the glove only.
- Verified here: the link cursor image becomes transparent while running and returns to the original after SIGTERM. The Arrow image reported by `CGSCreateRegisteredCursorImage` stayed unchanged while running, so on-screen confirmation is needed.
