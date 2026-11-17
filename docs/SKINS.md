# Designs (skins)

A design is either an **SVG design** (a folder with a `skin.json` manifest and SVG files, recommended) or a legacy **pixel** design (one JSON file with ASCII art). No code changes or rebuilds are needed.

## Where

```
~/Library/Application Support/Manita/Skins/<id>/skin.json   + idle.svg [, pressed.svg]  (SVG design)
~/Library/Application Support/Manita/Skins/<anything>.json                           (pixel design)
```

Open it from the menu: **Designs → Open Designs Folder…**, then **Reload Designs**. Invalid designs are skipped and logged (`log stream --predicate 'process == "Manita"'`).

## SVG designs

The only bundled design is the **Glove** (`cartoon`, `Resources/Skins/cartoon/`); the menu lists it first, then the designs in your designs folder. While the Glove is the only design, the design list is hidden. A saved design that no longer exists falls back to the first design, the Glove.

```
Skins/cartoon-blue/
├── skin.json
├── idle.svg         the hand (pointer)
├── sleeve.svg       the sleeve tile (optional, see Wand)
├── cuff.svg         the sleeve's cuff piece (optional, see Wand)
├── burst.svg        the click effect (optional, see Click effects)
└── pressed.svg      (optional)
```

A design has three parts you can draw: the **hand** (`svg.idle`), the **sleeve** (`wand.svg`) and the **click effect** (`click`). The bundled Glove draws all three as SVG (`idle.svg`, `sleeve.svg`, `burst.svg`).

> The app never shows the pressed artwork: the hand keeps its idle frame and a click is shown by the hop, burst and jab. `pressed.svg` is optional and currently not displayed (it is kept for compatibility, and `--render-preview` still draws it).

```json
{
  "id": "cartoon-blue",
  "name": "Cartoon Blue",
  "author": "you",
  "svg": { "idle": "idle.svg", "pressed": "pressed.svg" },
  "hotspot": { "x": 34.3, "y": 11.5 },
  "armAnchor": { "x": 65.3, "y": 82.7 },
  "wand": { "style": "sleeve", "color": "#112244", "width": 34 },
  "click": { "bursts": ["rays", "star"], "weight": 1.2 }
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique identifier. Reusing the id of an existing design (such as `cartoon`) replaces it. |
| `name` | yes | Label shown in the menu. |
| `author` | no | Credit. |
| `svg.idle` | yes | Resting hand. A plain file name in the same folder, ending in `.svg`. |
| `svg.pressed` | no | Optional, currently not displayed by the app (kept for compatibility); falls back to `idle`. When given, it must have the same `viewBox`. |
| `hotspot` | yes | Point, in the SVG's user units, that sits on the real click point (the fingertip). Must be inside the `viewBox`. |
| `armAnchor` | no | Where the arm attaches, in user units (bottom of the cuff). Default: bottom center. |
| `wand` | no | The wand ("varita") behind the hand; see [Wand](#wand). |
| `click` | no | The click effects; see [Click effects](#click-effects). |
| `armWidth` | no | Older name of `wand.width`; `wand.width` wins when both are set. |
| `arm` | no | Older name of `wand.color` (and the default burst color), `#RRGGBB`. Default `#111111`. |

The **Color** setting overrides every color of the wand and the effects, except *Design's Own*, which uses the design's. The **Pointer Mood** still scales the wand's width (×0.7, ×0.9, ×1.05, ×1.2 from the lowest to the highest stop) and length, and the size of the click hop and burst.

Rules (checked by `Skin.validate()`; the root `<svg>` is read for its `viewBox`, or `width`/`height` when there is none):

- File names cannot contain a path (`/`, `..`); a missing file, a file that is not an SVG, or a `pressed` with a different `viewBox` rejects the design. The same goes for the files named by `wand.svg` and `click.svg`.
- The longer side of the `viewBox` is drawn at `Size × 13` points (Size 1–8; the default Size 5 ≈ 65 pt), aspect ratio preserved, at Retina resolution.
- The wand (the menu calls it the sleeve) is drawn by the app (a bar from `armAnchor`, opaque then fading out, unless `wand` says otherwise), leaning 20° down-right: tilt the glove about 20° to the left so the cuff lines up with it. Its length, opacity and how soon it fades come from the **Pointer Mood**, not from the design.
- Preview the whole pointer with a mood and appearance: `.build/debug/Manita --render-pointer out.png path/to/design-folder 5 3 dark` (a bundled id such as `cartoon` works too).
- Use the macOS SVG subset: paths, basic shapes, `fill`, `stroke`, `transform`. Avoid scripts, filters, external references and text.
- Preview: `.build/debug/Manita --render-preview out.png path/to/design-folder 6`.

### Wand

```json
"wand": { "color": "#C8CCD2", "width": 7, "style": "stick", "fade": false }
```

| Field | Default | Meaning |
| --- | --- | --- |
| `color` | `arm`, else `#111111` (`#C8CCD2` for a `stick`) | `#RRGGBB` or `#RRGGBBAA`. |
| `width` | `armWidth`, else 30% of the `viewBox` width | Thickness in user units; must be above 0. |
| `style` | `sleeve` | `sleeve`: a solid bar as wide as the cuff (today's look). `stick`: a metal telescopic pointer: three tube segments, each thinner than the last away from the hand, joined by collars. |
| `fade` | `true` for `sleeve`, `false` for `stick` | Whether the wand fades out along its length. A sleeve that does not fade keeps the mood's opacity along its whole length; a stick is fully opaque. |
| `svg` | none | The design's own sleeve: `{ "tile": "sleeve.svg", "cuff": "cuff.svg" }` (`cuff` optional). Replaces `style`. See below. |
| `tint` | `false` | With `svg`: draw the sleeve art in the wand color (its shapes are used as a mask), so `color` and the **Color** setting apply to it. Without it the art keeps its own colors. |

#### Drawing your own sleeve

```json
"wand": { "width": 30, "svg": { "tile": "sleeve.svg", "cuff": "cuff.svg" }, "tint": false }
```

The sleeve is drawn as a strip that starts at `armAnchor` and runs away from the hand, as long as the **Pointer Mood** asks:

- `cuff` (optional) is drawn once, at the hand end (a quarter of the width is tucked under the hand).
- `tile` is repeated after it until the sleeve ends; it is never stretched.
- Draw both upright: top = toward the hand, bottom = away from it. Each file's `viewBox` width spans the sleeve's `width`; its height keeps the aspect ratio (a `0 0 30 20` tile on a 30-unit sleeve repeats every 20 units).
- The mood still sets the length, width, opacity and fade (`fade`).

The Glove's `sleeve.svg` is a plain 30 × 30 tile with `tint: true`, which looks exactly like the `sleeve` preset.

### Click effects

```json
"click": { "bursts": ["ring", "star", "rays"], "color": "#FF3366", "weight": 1.2 }
```

| Field | Default | Meaning |
| --- | --- | --- |
| `bursts` | `classic` | Burst kinds, cycled one per effect, in order: `classic`, `rays`, `star`, `ring`. An empty list means the default. `classic` is the website's burst: 12 straight rays around a filled 10-point star, about 1.6× the hand's size at the default mood, behind the hand; its rotation, size and star position are randomized on every click. Its rays and star fill use `color` (always, whatever the **Color** setting says, so the design keeps its look); the star outline uses the wand's color, which the **Color** setting does change. |
| `color` | the wand's color | `#RRGGBB` or `#RRGGBBAA`. |
| `weight` | `1` | Line width multiplier, from 0.25 to 4. |
| `svg` | none | The design's own click art: SVG files cycled one per effect. Replaces `bursts`. See below. |
| `size` | `1.6` | With `svg`: size of the art in hand sizes at the default mood (from 0.25 to 6). |
| `tint` | `false` | With `svg`: draw the art in `color` (its shapes are used as a mask), so the **Color** setting applies to it. Without it the art keeps its own colors. |
| `animation` | see below | With `svg`: how the art plays. |

#### Drawing your own click effect

```json
"click": {
  "svg": ["burst.svg", "pow.svg"],
  "size": 1.6,
  "animation": { "from": 0.4, "to": 1.15, "duration": 0.4, "spin": true, "fade": true }
}
```

The art is drawn centered on the click point, behind the hand, in a square `size` hands wide (the longer side of its `viewBox` fills it). The app animates it; SVG animation (SMIL, CSS) is not played.

| `animation` field | Default | Meaning |
| --- | --- | --- |
| `from`, `to` | `0.4`, `1.15` | Scale at the start and at the end (1 = `size`), from 0 to 4. |
| `duration` | `0.4` | Seconds, from 0.05 to 2. |
| `spin` | `true` | Turn the art to a random angle on every click. |
| `fade` | `true` | Fade out while it plays. |

The **Pointer Mood** and the click streak scale it like the `classic` burst. The Glove's `burst.svg` is the classic burst (12 rays around a 10-point star) drawn as SVG, with the defaults above.

Effects play from the click number chosen in the menu's **Effects From Click** (default 3; a rapid streak is clicks less than 0.45 s apart); they take about 0.3 s (0.4 s for `classic`, which has no trailing ring) and, for the other kinds, the faint ring that follows lasts at most 0.35 s after the burst. A design with an unknown `style` or burst kind, a bad color or an out-of-range `width`/`weight` is rejected and logged. These fields apply to SVG designs only; `svg.idle` is the cursor artwork.

## Pixel designs (legacy)

### Format

```json
{
  "id": "neon",
  "name": "Neon",
  "author": "you",
  "palette": {
    "#": "#00FFCC",
    "w": "#1A1A2E",
    "s": "#FF00AA80"
  },
  "frames": {
    "idle": [
      "..##..",
      ".#ww#.",
      ".#ww#.",
      "#wwww#",
      "#ssss#",
      "######"
    ],
    "pressed": [
      "......",
      "..##..",
      ".#ww#.",
      "#wwww#",
      "#ssss#",
      "######"
    ]
  },
  "hotspot": { "x": 2, "y": 0 }
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique identifier. Reusing the id of an existing design replaces it. |
| `name` | yes | Label shown in the menu. |
| `author` | no | Credit. |
| `palette` | yes | One-character symbol → `#RRGGBB` or `#RRGGBBAA`. |
| `frames.idle` | yes | Resting hand. |
| `frames.pressed` | no | Optional, currently not displayed by the app; falls back to `idle`. |
| `hotspot` | yes | Pixel (top-left origin, inside `idle`) that sits on the real click point. |

Rules (checked by `Skin.validate()`):

- `.` and space are transparent.
- Every row in a frame has the same width; frames may differ in size.
- Every non-transparent character must exist in `palette`.

Pixel art is scaled by whole numbers (the **Size** setting, 1–8), so keep designs small: 12–24 px works well.

Pixel designs have no `wand` or `click` fields: the arm is 28% of the hand width (scaled by the **Pointer Mood** like `armWidth`) and, with **Color** set to *Design's Own*, uses the palette's `#` color (black when there is none).

## Adding a built-in design

- **SVG design:** add a folder under `Resources/Skins/<id>/` and list it in `BuiltInSkins.folders` (`Resources/Skins/BuiltInSkins.swift`) and in the `resources:` of the `ManitaSkins` target in `Package.swift`. Add a test like `bundledCartoonIsValid`. The app is meant to ship the Glove only, so prefer the designs folder.
- **Pixel design:** the `classic` and `pocket` constants in `Sources/ManitaCore/SkinRegistry.swift` stay in code for the pixel format and the tests; the app does not register them.

The old `vector` recolor kind (code-drawn glove) was removed; a JSON file that only has `vector` is rejected as an invalid pixel design.
