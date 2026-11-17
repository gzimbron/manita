# Changelog

All notable changes are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [1.0.0] - 2026-11-16

First public release.

### Added

- Menu bar app that turns the pointer into an old-cartoon gloved hand with a long trailing sleeve, following the pointer in every app, Space, full-screen window and display (one click-through overlay surface per screen). The hand itself is never recolored.
- The **Glove**, drawn as original SVG artwork, is the only bundled design. Add your own in `~/Library/Application Support/Manita/Skins/` (a folder with `skin.json` and SVGs; `Designs → Open Designs Folder…` and `Reload Designs`). Each design configures its `wand` (sleeve or telescopic stick) and its `click` effects; see `docs/SKINS.md`. Legacy pixel-art JSON designs still load.
- Every click hops the hand up and to the left and plays a short, natural click sound synthesized in code. The hand keeps its idle artwork while it hops.
- Rapid clicks (less than 0.45 s apart) form a streak. From the **Effects From Click** number (default 3, from 1 to 10) the classic burst plays: 12 rays and a red star, with rotation, size and star position randomized on every click. From the third rapid click (or that number, if higher) the hand also jabs and shakes with a trailing copy. Effects last well under half a second and leave nothing behind.
- **Pointer Mood**: a four-stop slider from *Subtle* to *Look at me!* (default: the second) that makes the sleeve wider, longer and more opaque, and the hop and the burst bigger.
- **Color** of the sleeve and click effects: *Automatic (Light/Dark)*, *Black*, *White* or *Design's Own*.
- **Size** from 1× to 8× (default 5×), click sound on/off with volume, **Show Sleeve**, **Animate on Click**, **Hide System Pointer** (replaces the system cursors with a transparent image, falling back to hiding the pointer) and **Launch at Login**.
- **Global shortcuts**: `⌃⌥P` shows or hides the pointer and `⌃⌥T` turns presentation mode on or off. Both can be changed in **Shortcuts** (with **Reset to Defaults**) and need no permission.
- **Presentation mode**: clicks are held back from every app while the hand still animates, so slides do not advance. Needs Accessibility permission, refuses to start without its exit shortcut, ends when the pointer is hidden, is never restored on launch, and shows an on-screen notice with the exit shortcut.
- App icon, and a bilingual (English and Spanish) website at <https://gzimbron.github.io/manita/>.
- `--render-preview` and `--render-pointer` command-line options to render a design or the whole pointer to PNG.
- Distribution: tag-driven GitHub Actions release that builds, signs (Developer ID), notarizes, publishes the GitHub Release and updates the Homebrew cask (`brew install --cask gzimbron/tap/manita`); CI builds and tests every push and pull request.

[1.0.0]: https://github.com/gzimbron/manita/releases/tag/v1.0.0
