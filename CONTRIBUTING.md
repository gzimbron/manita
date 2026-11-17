# Contributing

Thanks for your interest! Manita is small on purpose; keep changes focused.

## Setup

```sh
git clone https://github.com/gzimbron/manita.git && cd manita
make test   # or: swift test
make open   # or: scripts/build-app.sh debug && open build/Manita.app
```

Run `make` to list every shortcut; see [Make shortcuts](README.md#make-shortcuts).

## Conventions

- Swift 6, strict concurrency. AppKit types are `@MainActor`.
- Logic goes in `ManitaCore` with tests; the `Manita` target stays a thin AppKit shell. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- New preferences need a default and must decode with `decodeIfPresent`, so existing users keep their settings.
- No binary assets unless an ADR says otherwise (pointer art is SVG or ASCII, sound is synthesized; the app icon is the one exception).
- Significant decisions get an ADR in `docs/adr/` (copy the format of an existing one, next number).
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `chore:`…
- Update `CHANGELOG.md` under an `## [Unreleased]` section (add it above the latest release when needed); it is renamed to the version when releasing (see [docs/RELEASING.md](docs/RELEASING.md)).

## Manual checklist (AppKit layer)

Before opening a PR that touches `Sources/Manita`:

- [ ] Hand follows the pointer over other apps, across displays and in a full-screen app.
- [ ] Every click hops the hand up-left (the hand never swaps to the pressed artwork); a rapid streak plays the classic burst from the **Effects From Click** number (default 3) and the jab/shake with trail from max(that, 3); turning off **Animate on Click** stops all of it.
- [ ] Click plays the sound; turning off **Click Sound** silences it; volume changes apply.
- [ ] **Hide System Pointer** hides/shows the arrow; quitting always restores it.
- [ ] **Hide Pointer** (`⌃⌥P`) hides the hand and stops all effects; **Show Pointer** brings it back.
- [ ] **Presentation Mode** (`⌃⌥T`) holds clicks back while the hand still animates, and the shortcut exits it.
- [ ] **Show Sleeve** toggles the arm.
- [ ] Size, Color, Pointer Mood and Effects From Click changes apply immediately and persist after relaunch.
- [ ] Cartoon glove renders from the SVGs, also in `build/Manita.app` (`scripts/build-app.sh`), and the arm is solid near the cuff and fades at its far end.
- [ ] Design art changes: check `--render-preview out.png <design> 6` and `--render-pointer out.png <design> 5 1 light`.

## Designs

Contributing a design? See [docs/SKINS.md](docs/SKINS.md). Designs (SVG folders preferred) must be original work.
