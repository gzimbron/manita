# Manita 👆

A tiny macOS menu bar utility that turns your pointer into an **old-cartoon gloved hand** with a long trailing sleeve (or a telescopic pointer, if a design asks for it), a hop on every click, a burst and a jab on rapid clicks, and a natural click sound. Every effect can be switched off.

Current version: **1.0.0**, the first public release. Website: <https://gzimbron.github.io/manita/> (Spanish: <https://gzimbron.github.io/manita/es/>).

## Install

```sh
brew install --cask gzimbron/tap/manita
```

Or download the signed and notarized `Manita-<version>.zip` from [GitHub Releases](https://github.com/gzimbron/manita/releases), unzip it and move `Manita.app` to Applications. Requires macOS 26 or later. To build it yourself, see [Build and run](#build-and-run).

## Features

- A hand that follows the pointer across every app, Space and full-screen window. The only bundled design is the **Glove** (SVG artwork); add your own SVG (or legacy pixel) designs in the designs folder. Each design draws its hand and, optionally, its own sleeve (`wand.svg`) and click effect (`click.svg`), configured in `skin.json` (see [docs/SKINS.md](docs/SKINS.md)).
- On every click the hand (and its sleeve) hops up and to the left, where the finger points, and springs back, and a short, natural click sound (synthesized in code) plays. The hand always keeps its idle artwork; it never swaps to a pressed frame.
- **Rapid clicks** (presses less than 0.45 s apart) form a streak. From the click number set in **Effects From Click** (default 3, from 1 to 10) the classic burst plays where the click landed: 12 rays and a red star, with rotation, size and star position randomized on every click. From the third rapid click (or the chosen number, if higher) the hand also jabs and shakes sideways with a faded trailing copy, and each further click in the streak hits slightly harder (capped). The effects take well under half a second and leave nothing behind.
- **Pointer Mood**: a four-stop slider from *Subtle* to *Look at me!* (default: the second stop). It never changes the hand itself, only the sleeve and how hard a click lands:
  - the sleeve gets wider, longer and more opaque (at the lowest stop it is thin, short and translucent);
  - the click hop goes further;
  - the burst gets bigger.
- **Color** of the sleeve and click effects: *Automatic (Light/Dark)* (black on a light desktop, translucent light gray in Dark Mode, switching when macOS does), *Black*, *White*, or *Design's Own* (the design's own colors, or a pixel design's outline). The hand artwork itself is never recolored, and the classic burst keeps the design's red accent for its rays and star (only the star outline follows the setting).
- **Global shortcuts**, changeable from the menu: `⌃⌥P` shows/hides the pointer, `⌃⌥T` turns presentation mode on/off.
- **Presentation mode**: click anywhere to call out details without pressing anything (see [Presentation mode](#presentation-mode)).
- Fully configurable from the menu bar (see [Menu](#menu)): size 1×–8× (default 5×), sound and volume, click animation and when effects start, sleeve, hiding the system pointer, your own SVG designs, launch at login.
- The pointer is drawn on every display (one overlay surface per screen), so the hand and its sleeve cross from one screen to the next without vanishing.
- No bundled audio or raster assets for the pointer: art is SVG, and the click sound is generated in code.

## Requirements

- macOS 26 or later
- Xcode 26+ / Swift 6.2+ (for building)

## Build and run

```sh
scripts/build-app.sh          # release build -> build/Manita.app
open build/Manita.app
```

For development:

```sh
swift build                   # compile
swift test                    # run unit tests (ManitaCore)
scripts/build-app.sh debug    # debug .app bundle
```

Or use the `Makefile` shortcuts (`make` lists them all):

```sh
make open                     # quit Manita, rebuild the debug app and open it
make build | make test | make release | make clean
make pointer DESIGN=cartoon MOOD=3 APPEARANCE=dark   # render the pointer and open the PNG
make preview DESIGN=path/to/design-folder            # render a design's artwork
```

The icon appears in the menu bar (there is no Dock icon). Quit from the menu.

### Permissions

Outside presentation mode Manita only *observes* mouse events, it never changes or blocks clicks. If macOS asks for **Accessibility** or **Input Monitoring** access, grant it in *System Settings → Privacy & Security*; without it the hand may not follow the pointer over other apps.

Presentation mode needs **Accessibility** permission (*System Settings → Privacy & Security → Accessibility*). The global shortcuts need no permission.

`scripts/build-app.sh` signs with your first "Apple Development" certificate so the permission survives rebuilds (override with `MANITA_SIGN_IDENTITY`). Without a certificate it signs ad-hoc, and the permission must be granted again after every rebuild: remove Manita from the list with "−" and add it again. Official releases are signed with a Developer ID certificate and notarized, so the permission survives updates (see [docs/RELEASING.md](docs/RELEASING.md)).

## Usage

### Menu

From top to bottom:

| Item | What it does |
| --- | --- |
| **Hide Pointer** / **Show Pointer** `⌃⌥P` | Turns Manita off (the hand disappears, the system pointer comes back) or on. Hiding the pointer also leaves presentation mode. |
| **Presentation Mode** `⌃⌥T` | Checked while presentation mode is on. |
| **Pointer Mood** slider | *Subtle* … *Look at me!*, four stops. |
| Design list | The Glove and your own designs. Hidden while the Glove is the only design. |
| **Color ▸** | *Automatic (Light/Dark)*, *Black*, *White*, *Design's Own*. |
| **Size ▸** | 1× to 8× (default 5×). |
| **Designs ▸** | *Open Designs Folder…*, *Reload Designs*. |
| **Animate on Click** | Click hop, burst and jab on/off. |
| **Effects From Click ▸** | From which click of a rapid streak the burst plays: *Every Click*, or *Click 2 of a Streak* … *Click 10 of a Streak* (default *Click 3 of a Streak*). The jab and shake start from the third click or this number, whichever is higher. |
| **Click Sound**, **Volume ▸** | Sound on/off; 25%, 50%, 75%, 100%. |
| **Show Sleeve** | The trailing sleeve on/off. |
| **Hide System Pointer** | Hide the real macOS pointer under the hand. |
| **Shortcuts ▸** | Change the two global shortcuts, or *Reset to Defaults*. |
| **Launch at Login**, **About Manita**, **Quit Manita** `⌘Q` | |

The shortcuts shown next to the first two items are the current global shortcuts; they work anywhere, with the menu closed.

### Shortcuts

Defaults: `⌃⌥P` (control-option-P) shows or hides the pointer, `⌃⌥T` (control-option-T) turns presentation mode on or off.

To change one, choose **Shortcuts → Show/Hide Pointer: ⌃⌥P…** (or **Presentation Mode: ⌃⌥T…**) and press the new combination in the *Record Shortcut* window. It must include ⌃, ⌥ or ⌘ (Shift alone is not enough) and cannot be the other action's shortcut. `Esc` or *Cancel* keeps the current one. **Shortcuts → Reset to Defaults** restores both. If another app already owns a shortcut, Manita cannot register it (logged as `could not register shortcut`); pick a different one.

### Presentation mode

For demos and slides: the pointer stays visible and animates on every click, but clicks are **held back** from every app, so nothing gets pressed and your slides do not advance. Dragging only moves the pointer; scrolling and the keyboard keep working.

- Turn it on with `⌃⌥T` or **Presentation Mode** in the menu. A notice shows the exit shortcut with a progress bar, then fades out; another one confirms when it is off.
- **The shortcut is the only way out**: clicks on the menu bar (including Manita's own menu) are held back too. Hiding the pointer (`⌃⌥P`) also leaves presentation mode.
- Manita refuses to start it when its exit shortcut could not be registered (for example, another app uses it) and asks you to choose a different one in **Shortcuts**. If the pointer was hidden, starting presentation mode shows it.
- It needs **Accessibility** permission. Without it Manita offers to open *System Settings → Privacy & Security → Accessibility*; allow Manita there, then try again.
- It is never restored on launch: Manita always starts with working clicks.

## Custom designs

Designs ("skins") are folders with a `skin.json` and SVG files (`idle.svg`, optionally `pressed.svg`, which the app does not currently display); legacy pixel designs are single JSON files. Put them in:

```
~/Library/Application Support/Manita/Skins/
```

then choose **Designs → Reload Designs** in the menu. Format and examples: [docs/SKINS.md](docs/SKINS.md). Preview a design without launching the app:

```sh
swift build && .build/debug/Manita --render-preview preview.png path/to/design-folder 6
```

`--render-preview <out.png> [design-id|design folder|design.json] [scale 1-8]` draws the idle and pressed artwork side by side (a preview aid; the app itself only shows the idle frame). Defaults: the Glove, scale 6.

To see the whole pointer as it looks on screen (sleeve, hand and the classic click burst) for one mood:

```sh
.build/debug/Manita --render-pointer pointer.png cartoon 5 3 dark
```

`--render-pointer <out.png> [design-id] [scale 1-8] [mood 0-3] [light|dark]` takes the bundled design id (`cartoon`), a design folder or a `.json` file, and uses the *Automatic* color for the given appearance. Defaults: `cartoon`, scale 5, mood 1, `light`. Very long sleeves are cut off at 700 pt.

## Documentation

| Document | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, data flow, where to change what |
| [docs/SKINS.md](docs/SKINS.md) | Design (skin) format: SVG folders and pixel JSON |
| [docs/RELEASING.md](docs/RELEASING.md) | Signing, notarization, GitHub Releases and the Homebrew tap |
| [docs/adr/](docs/adr/) | Architecture decision records |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Workflow, conventions, tests |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Known limitations

- Hiding the system pointer relies on private macOS APIs: system cursors are replaced by a transparent image while Manita runs (see [ADR 0005](docs/adr/0005-replace-system-cursors.md)). If that fails Manita falls back to hiding the pointer, and then to showing it under the hand.
- Manita restores the cursors when you quit, disable it, or when it receives SIGTERM/SIGINT. If it crashes or is force-killed (SIGKILL), the pointer may stay invisible: relaunch Manita and quit it (or turn off *Hide System Pointer*), or log out and back in.
- Builds you compile yourself are not notarized: on first launch you may need right-click → *Open*. Release downloads and the Homebrew cask are notarized.

## License

[MIT](LICENSE) © 2026 Gustavo Zimbrón. Inspired by the idea behind apps like Pokey; all art, sound and code here are original.
