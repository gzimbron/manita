# ADR 0004: Vector cartoon glove as the default design

- Status: partly superseded by [ADR 0006](0006-svg-skins.md) (the glove is now SVG, not drawn in code; the arm, burst and preview decisions stand)
- Date: 2026-11-16

## Context

The target look is an old-cartoon (1930s "rubber hose") white glove with a thick outline, a long arm trailing behind the pointer and burst lines on click, not 8-bit pixel art. Pixel art (ADR 0002) cannot scale smoothly to that look.

## Decision

- `Skin` gains an optional `vector` field (`fill`, `outline`, `cuff` colors). When present, the app draws an original glove from rounded shapes (`GloveRenderer`) at Retina resolution; pixel fields are ignored.
- The cartoon glove is the default design. Pixel designs stay available.
- The arm is a thick line from the cuff, fading out, drawn by the overlay for every design and toggled by the **Show Arm** preference.
- The click effect is a burst of short rays above the click point (replaces the ripple).
- `Manita --render-preview <out.png> [design] [scale]` renders a design to PNG for review.

## Consequences

- Vector designs can only recolor the built-in glove; new shapes need code (a new renderer behind `HandArtwork`).
- The overlay panel is larger, to fit the arm; it still ignores all mouse events.
- All artwork remains original and generated in code.

Update (1.0.0): the **Show Arm** preference is now **Show Sleeve**, and the click effect is no longer a plain ring of short rays: every click hops the hand, and the classic burst (12 rays and a star) and a jab play from a rapid click streak (see [ARCHITECTURE.md](../ARCHITECTURE.md)). The default design is the SVG Glove (ADR 0006); pixel designs are not registered by the app.
