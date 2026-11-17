# Architecture

Manita is a SwiftPM package with three targets (`ManitaCore`, `Manita`, and `ManitaSkins`, which only carries the bundled SVG designs as resources). The split keeps all logic that can be tested without a screen out of AppKit.

```
Sources/
├── ManitaCore/            pure Swift, no AppKit — unit-tested
│   ├── Preferences.swift      settings model + UserDefaults store
│   ├── Mood.swift             Mood levels → MoodStyle (sleeve + click)
│   ├── Hotkey.swift           global shortcut value (key code, label, modifiers), defaults
│   ├── Skin.swift             design model (SVG or pixel), validation, PixelImage
│   ├── SVGDocument.swift      reads an SVG root (viewBox) for validation
│   ├── DesignStyle.swift      per-design `wand` and `click` configuration (decoding, defaults, validation)
│   ├── SkinRegistry.swift     pixel constants, design folder / JSON loading, fallback to the first design
│   ├── ClickStreak.swift      rapid-press counter (< 0.45 s apart): which press a streak is on, growing intensity
│   ├── ClickSound.swift       natural click synthesized from seeded noise
│   ├── RetroSound.swift       square-wave synth (legacy) + WAV encoder
│   └── CursorOverride.swift   cursor names, transparent image spec, fallback policy
Resources/Skins/           bundled SVG designs (target ManitaSkins, Bundle.module)
│   ├── BuiltInSkins.swift     where the bundled design folders are
│   └── cartoon/               skin.json, idle.svg (hand), sleeve.svg (sleeve tile), burst-lines/stars/kaboom.svg (click effects, cycled): the Glove, the only bundled design
└── Manita/                AppKit shell — thin, manually tested
    ├── main.swift             app entry (accessory / menu bar only), preview flags
    ├── AppDelegate.swift      composition root: owns state, applies preferences
    ├── MouseMonitor.swift     global + local mouse event monitors
    ├── OverlayController.swift one static click-through panel per display (PointerSurface); moves the pointer, plays effects
    ├── PointerSurface.swift    per-display panel + pointer layer tree (trail → body → sleeve/stick + hand) + burst layers
    ├── HandArtwork.swift      renders a Skin (SVG via NSImage, or pixel art) to images
    ├── HotkeyCenter.swift     system-wide shortcuts (Carbon RegisterEventHotKey)
    ├── ShortcutRecorder.swift "Record Shortcut" window that captures a new Hotkey
    ├── ClickDisarmer.swift    presentation mode: session event tap that swallows clicks
    ├── PresentationNotice.swift on-screen notice when presentation mode turns on/off
    ├── PreviewRenderer.swift  `--render-preview` and `--render-pointer` PNG output
    ├── SoundPlayer.swift      AVAudioPlayer pool for the click sound
    ├── SystemCursorHider.swift replaces/hides the real pointer (private API, guarded)
    └── StatusMenuController.swift menu bar icon and settings menu
```

## Data flow

```
MouseMonitor ──move──▶ OverlayController.move(to:)
      │
      └──down/up──▶ AppDelegate.handleButton ──▶ ClickStreak.press ──▶ OverlayController.setPressed
                                                                      (every press: bounce; from `effectsFromClick`:
                                                                      classic burst; from max(that, 3): jab + shake + trail)
                                              └─▶ SoundPlayer.playClick   (every press, if sound on)
ClickDisarmer ─swallowed down/up─▶ AppDelegate.handleButton   (presentation mode only)

HotkeyCenter ──action──▶ AppDelegate.toggle ──▶ show/hide pointer, or start/stopPresentation
StatusMenuController ──item──▶ AppDelegate.toggle / recordShortcut ──▶ ShortcutRecorder
StatusMenuController ──change──▶ AppDelegate: mutate Preferences → clamp → save → apply()
Light/Dark Mode change (NSApp.effectiveAppearance) ──▶ apply()

apply() pushes preferences into Overlay (design, size, sleeve, MoodStyle, design variant for the current appearance),
SoundPlayer and SystemCursorHider, registers the shortcuts, leaves presentation mode if it
lost its pointer or its exit shortcut, and rebuilds the menu.
```

`AppDelegate.apply()` is the single place where preferences turn into behavior. Adding a setting means: a field in `Preferences` (with a default, decoded with `decodeIfPresent`), a menu entry, and one line in `apply()` or `handleButton`.

### Components

- **`OverlayController`** owns one borderless, click-through, full-frame panel per `NSScreen` (`PointerSurface`, `.screenSaver` level), rebuilt on `NSApplication.didChangeScreenParametersNotification` and on `configure`. Each surface holds its own copy of the pointer layers (`PointerLayers`: a `CAReplicatorLayer` for the jab trail → body → sleeve/stick + hand) and of the burst and lingering ring, all built by the same `PointerSurface.apply(PointerSpec)`. Moving the pointer only sets the pointer layer position (screen-local coordinates, actions disabled) on the displays the hand touches, so the hand and sleeve are drawn in parts across displays and never vanish at the edge between two; displays with nothing to draw have their panel ordered out. Jab, bounce and shake animate every copy; a burst is placed at the click point on every surface and shows on the display that holds it. `configure(skin:scale:showArm:mood:)` takes the design already resolved for the current appearance (`Skin.resolved(for:)`). The hand always shows the idle artwork (`pressed` is rasterized by `HandArtwork` but never put on screen); a click is shown by motion alone: `playBounce` (every click: the hand and sleeve hop up-left, where the finger points, and settle), `playJab` (the shake with a two-copy trail, 280 ms) and `playBurst` (the classic burst: 12 rays and a filled star, with a random rotation, size and star position per click).
- **`MoodStyle`** (`ManitaCore/Mood.swift`) is the single source of the mood-driven parameters: sleeve width (a multiple of the design's wand width), length (in hand heights), opacity and fade point; hop distance (`jabDistance`) and shake; burst size (`burstRadius`, relative to the default mood) and line weight. Its ray count, comic and linger fields only matter to the non-default burst kinds a design may list (`rays`, `star`, `ring`); the classic burst is always 12 rays. `Mood.style(level)` maps the four levels (`Mood.range` 0…3, default 1) to fixed styles; the overlay reads nothing else. Hand size stays with the separate **Size** preference.
- **`Appearance` / `SkinVariant`** (`ManitaCore/SkinVariant.swift`): the optional `light` and `dark` blocks of `skin.json`. `Skin.resolved(for:)` returns the design with that block applied over the base; `AppDelegate.apply()` picks the appearance from `NSApp.effectiveAppearance`. There is no user color setting: a saved `pointerColor` preference is ignored. The hand artwork is never recolored by the app.
- **`ColorScheme`** (`ManitaCore/SkinVariant.swift`): the optional `colors` list of `skin.json`. `Skin.resolved(for:scheme:)` applies base → scheme overrides → scheme's (or the design's) appearance block; `Preferences.colorSchemes` remembers the choice per design and the design list in `StatusMenuController` (a submenu per design with 2+ schemes) changes it through `apply()`.
- **`HotkeyCenter`** registers `Hotkey` values for its two actions (`togglePointer`, `togglePresentation`) with Carbon `RegisterEventHotKey` and calls `onAction`. `register(_:)` returns the actions that failed; `isRegistered(_:)` tells whether a shortcut is live. See [ADR 0007](adr/0007-global-hotkeys-carbon.md).
- **`ShortcutRecorder`** opens a small *Record Shortcut* panel, reads one key press with a local monitor, rejects shortcuts without ⌃/⌥/⌘ and those `validate` refuses (the other action's shortcut), and calls `completion` once (`nil` on Esc, Cancel or close). `AppDelegate` unregisters all hotkeys while it is open, so pressing the current shortcut records it, and re-registers them afterwards.
- **`ClickDisarmer`** is presentation mode's engine: a session event tap that drops mouse button events, rewrites drags to moves, and reports each dropped press/release through `onButton` (wired to `handleButton`, so the hand still animates). Needs Accessibility permission. See [ADR 0008](adr/0008-presentation-mode-event-tap.md).
- **`PresentationNotice`** shows a transient, click-through card on the screen with the mouse: on entry, the exit shortcut as key caps and a progress bar (6 s); on exit, a short confirmation.

Presentation mode lives only in `ClickDisarmer.isActive`, never in `Preferences`. `AppDelegate.startPresentation()` checks, in order, that the presentation shortcut is registered and that the tap can be created, then shows the pointer if it was hidden and the entry notice. `stopPresentation()` removes the tap, resets the overlay's click state and shows the exit notice. `applicationWillTerminate` stops the tap and unregisters the hotkeys.

## Beyond the app

- `web/` is the Astro website (English at `/manita/`, Spanish at `/manita/es/`), deployed to GitHub Pages by `.github/workflows/pages.yml` when `web/**` changes on `main`.
- `.github/workflows/ci.yml` builds and tests every push to `main` and every pull request; `.github/workflows/release.yml` turns a `v*` tag into a signed, notarized GitHub Release and a Homebrew cask bump (see [RELEASING.md](RELEASING.md)).
- `Resources/Icon/` holds the app icon (`icon.svg` master, built `Manita.icns`), `scripts/` the build, icon and release scripts, and `packaging/homebrew/manita.rb` the cask template.

## Key decisions

- **Overlay window, not `NSCursor`** — macOS has no public API for a system-wide custom cursor. See [ADR 0001](adr/0001-overlay-window.md).
- **Artwork is SVG** — the bundled Glove and user designs are SVG files in a design folder; the wand and click burst are drawn by the app, configured by the design's `wand` and `click`. See [ADR 0006](adr/0006-svg-skins.md) (supersedes the code-drawn glove of [ADR 0004](adr/0004-vector-cartoon-glove.md)).
- **Designs are data** — a manifest plus files, so new designs need no code; pixel art remains as a legacy kind. See [ADR 0002](adr/0002-data-driven-skins.md) and [SKINS.md](SKINS.md).
- **The real pointer is replaced by a transparent cursor** (private API, Mousecape technique) resolved at runtime, restored on exit, falling back to hiding and then to showing it. See [ADR 0005](adr/0005-replace-system-cursors.md) and [ADR 0003](adr/0003-hide-system-cursor-private-api.md).
- **No binary pointer assets** — sound is synthesized (`ClickSound`), pointer art is text (SVG or ASCII). The only binary is the app icon (`Resources/Icon/Manita.icns`, built from `icon.svg`). Everything is diffable and license-clean.
- **Global shortcuts use Carbon `RegisterEventHotKey`** — system-wide, no permission needed. See [ADR 0007](adr/0007-global-hotkeys-carbon.md).
- **Presentation mode is an active session event tap** — the one place Manita blocks input, guarded by safety rules (exit shortcut must be registered, hiding the pointer exits, never persisted). See [ADR 0008](adr/0008-presentation-mode-event-tap.md).

## Where to change what

| I want to… | Change |
| --- | --- |
| Add a built-in SVG design | `Resources/Skins/<id>/`, `BuiltInSkins.folders`, `Package.swift` resources |
| Add a pixel design in code (tests, format) | `SkinRegistry.swift` (a `Skin` constant); the app does not register it by default |
| Add an animation frame kind | `FrameKind` in `Skin.swift`, then use it in `OverlayController` |
| Change the click sound | `ClickSound.samples` (envelope, filter, tick) |
| Change when effects start or how they grow | `Preferences.effectsFromClick` (the menu's **Effects From Click**, default 3, 1…10), the jab's minimum of 3 in `AppDelegate.handleButton`, and `ClickStreak` (`window`, `effectThreshold`, `intensityStep`) |
| Change how fast effects exit | `Mood.burstDuration`, `Mood.maxLingerDuration`, the `styles` table; effects are cleared in `OverlayController.scheduleCleanup` |
| Add a setting | `Preferences` + `StatusMenuController.rebuild()` + `AppDelegate.apply()` |
| Tune a mood level (sleeve, jab, burst) | The `styles` table in `Mood.swift`; check with `--render-pointer` |
| Change the click effect | `OverlayController.playBounce()` / `playJab()` / `playBurst()`, `BurstShape` |
| Change the glove shape | Edit `Resources/Skins/cartoon/*.svg`; check with `--render-preview` |
| Change the wand | `OverlayController.configure` (angle) and `PointerLayers.apply` (tuck, `stickPath`) and the design's `armAnchor` and `wand`; length and fade come from `MoodStyle` |
| Change a default shortcut | `Hotkey.togglePointer` / `Hotkey.presentationMode` |
| Add a shortcut action | `HotkeyCenter.Action`, `ShortcutTarget`, a `Hotkey` field in `Preferences`, `AppDelegate.registerHotkeys()` / `toggle(_:)` |
| Change what presentation mode blocks | `DisarmTap` mask and `handle(_:_:)` in `ClickDisarmer.swift` |

## Testing

`swift test` (also run by CI on every push and pull request) covers `ManitaCore`: preference persistence and migration, skin validation (SVG folders, pixel art), the registry and folder loading, the bundled Cartoon files, sound synthesis, click streaks, per-design wand and click settings, mood styles and colors, and hotkey defaults, validation and conflict repair. The AppKit layer is kept thin and verified manually (see the checklist in [CONTRIBUTING.md](../CONTRIBUTING.md)).
