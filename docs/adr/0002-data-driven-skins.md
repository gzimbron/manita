# ADR 0002: Designs are data (ASCII pixel art in JSON)

- Status: accepted
- Date: 2026-11-16

## Context

More hand designs will be added over time, possibly by other people once the project is open source. Adding a design should not require touching rendering code or shipping binary assets.

## Decision

A `Skin` is a `Codable` value: palette (symbol → hex color), named frames (`idle`, optional `pressed`) as rows of characters, and a hotspot. `SkinRegistry` holds the built-ins and loads extra `*.json` files from `~/Library/Application Support/Manita/Skins`. `Skin.validate()` rejects malformed designs before they reach the UI.

## Consequences

- New designs are text: easy to review in a PR, diff and license.
- Missing optional frames fall back to `idle`, so new frame kinds (e.g. drag, right-click) can be added without breaking existing designs.
- Limited to pixel art; vector or photo designs would need a new frame source (e.g. a PNG path field) behind the same `Skin` interface.

Update (1.0.0): the app now ships one SVG design, the **Glove** (see [ADR 0006](0006-svg-skins.md) and [SKINS.md](../SKINS.md)). Pixel designs remain a supported legacy format (and the `classic`/`pocket` constants stay in code for tests), but the app no longer registers them; only designs in the user's Skins folder are loaded besides the Glove. `frames.pressed` is optional and currently not displayed.
