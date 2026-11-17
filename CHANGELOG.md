# Changelog

All notable changes are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/).

## [1.1.0](https://github.com/gzimbron/manita/compare/v1.0.0...v1.1.0) (2026-11-17)


### Features

* **about:** link the GitHub repository ([ec05643](https://github.com/gzimbron/manita/commit/ec05643fa15f0bd2778b1cb9ebe55f038f19b7e8))
* **click:** let up to five click art effects play at once ([8542f65](https://github.com/gzimbron/manita/commit/8542f65b8025b40ab76865294dd97682cb078964))
* **click:** scatter click art around the click and limit its random turn ([4ec2dff](https://github.com/gzimbron/manita/commit/4ec2dffdf1fc5cc74ec41c75010e8a7d6111499d))
* **menu:** group designs, their schemes and folder actions under Design ([0f41d7c](https://github.com/gzimbron/manita/commit/0f41d7cc2854a80c8e756a43596ac0bef7f4ea57))
* **prefs:** sizes start at the default look, shown as 1x to 8x ([e634564](https://github.com/gzimbron/manita/commit/e63456419e76245ecb6cd74d5b5609c57c7cd4b9))
* **skins:** add the Cat Paw design (claws, furry leg, Black/Tabby/Gray, cat effects) ([0b545f5](https://github.com/gzimbron/manita/commit/0b545f5c6546aafa37d6d3bcc02a2bb141ec1b7a))
* **skins:** add the Magic Wand design (star pointer, wand sleeve, Purple/Gold, magic effects) ([462ffc9](https://github.com/gzimbron/manita/commit/462ffc9b68f1e0c04cb44b7659db7a7d23be03b9))
* **skins:** give the Glove three click effects (rays, stars, kaboom) ([c8257f2](https://github.com/gzimbron/manita/commit/c8257f29252e4f9b5b319ec5a97935464e483734))
* **skins:** let designs draw their own click effect (click.svg + animation) ([f59efa6](https://github.com/gzimbron/manita/commit/f59efa6a72c612ba23e3ab4e000cd8a3eea645d6))
* **skins:** let designs draw their own sleeve (wand.svg tile + cuff) ([eabdd25](https://github.com/gzimbron/manita/commit/eabdd256ccf2f62fd4efccb42f7cbebba068cae2))
* **skins:** per-design color schemes replace the Color setting ([6142bba](https://github.com/gzimbron/manita/commit/6142bba4a860353e7c9b698c6a72eb8ccdaa7500))
* **web:** add design, color, size and mood selectors to the live demo ([921e1d6](https://github.com/gzimbron/manita/commit/921e1d6a623bf23e2a8a21390f397f9306ae8082))

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
