# ADR 0006: Artwork is SVG

- Status: accepted
- Date: 2026-11-16
- Supersedes: the artwork part of [ADR 0004](0004-vector-cartoon-glove.md)

## Context

The code-drawn glove of ADR 0004 (`GloveRenderer`, rounded rectangles and ellipses) was rejected: it did not look like a classic cartoon glove, and changing its shape meant changing Swift. The request was a cartoon style, "todo en svg".

## Decision

- A `Skin` has an `svg` kind: manifest `svg: { idle, pressed }`, `hotspot` and `armAnchor` in the SVG's user units, optional `armWidth` and `arm` (color). It lives in a folder with `skin.json` and the SVGs; `SkinRegistry.register(manifestAt:)` reads the files, `Skin.validate()` checks them (plain file names, files present, root `viewBox` parsed with `XMLParser`, `pressed` with the same box, hotspot and anchor inside it).
- The app rasterizes SVG with `NSImage(data:)` at Retina scale. The longer side of the `viewBox` is drawn at `Size × 13` points.
- The default Cartoon glove is `Resources/Skins/cartoon/`, bundled through a resource-only target `ManitaSkins` (`Bundle.module`). `scripts/build-app.sh` copies its bundle into `Manita.app/Contents/Resources`.
- User designs are folders in `~/Library/Application Support/Manita/Skins/`.
- `GloveRenderer` and the `vector` recolor kind are removed. Pixel designs stay as a legacy kind with `palette` and `hotspot` still required (ADR 0002 otherwise stands).
- The arm and click burst stay drawn by the app, for every design.

## Consequences

- A designer can change the glove in any vector editor; no Swift needed.
- Rendering depends on the macOS SVG subset (no filters, scripts or text); `--render-preview` is the check.
- Old `vector` JSON files no longer load (they are reported as invalid pixel designs).
- The core does not render SVG; only the root box is parsed there, so validation stays unit-testable.

Update (1.0.0): the bundled Glove is the only built-in design. Its `skin.json` also carries `wand` and `click` configuration (`docs/SKINS.md`), which supersede `arm`/`armWidth` (still read). The `pressed` artwork is optional and the app does not display it: the hand keeps its idle frame and a click shows as a hop, burst and jab.
