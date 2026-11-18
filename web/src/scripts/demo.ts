// Live demo: the chosen design follows the pointer inside the stage.
// Mirrors the app: every click makes the hand + sleeve hop up-left along the
// finger axis and spring back (the artwork never changes). From the 3rd rapid
// click (< 450 ms apart) the hand jabs and shakes, leaves two trailing
// copies and the design's click effect plays behind it. Design, colour, size
// and mood come from the controls above the stage (see skins.ts).

import { SKINS, MOODS, DEFAULT_MOOD, handPixels, type Skin, type Variant, type Mood } from "./skins";

const STREAK_MS = 450;
const SVG_NS = "http://www.w3.org/2000/svg";
const ARM_ANGLE = 20; // degrees from vertical, toward the bottom-right (OverlayController.armAngle)
// Finger axis: the idle art is tilted -20deg, so the finger points up-left.
const AXIS = { x: -Math.sin((20 * Math.PI) / 180), y: -Math.cos((20 * Math.PI) / 180) };
const SIDE = { x: -AXIS.y, y: AXIS.x }; // perpendicular, for the shake
const HOP_MS = 280;
const JAB_MS = 280;
const HOP = [0, 1, -0.3, 0.12, 0]; // multiples of the hop distance
const HOP_TIMES = [0, 0.28, 0.6, 0.82, 1]; // keyTimes of the hop (the jab is evenly spaced)
const HOP_EASING = ["ease-out", "ease-in-out", "ease-in-out", "ease-in"]; // per segment, as in the app
const TRAIL_ALPHA = [0.6, 0.2]; // constant opacity of the two trailing copies
const TRAIL_MS = 45; // delay between the hand and each trailing copy
const JAB = [0, 1.4, -0.25, 1.3, -0.25, 0.9, -0.1, 0]; // multiples of the hop distance
const HOP_DIST = 0.12; // of hand size, at the default mood (scaled by the mood's jabDistance)
const SHAKE = 0.07; // sideways, of hand size

let sleeveId = 0;

/** Draws the design's idle art and sleeve into the hand SVG, like PointerSurface + HandArtwork. */
function drawHand(svg: SVGSVGElement, skin: Skin, variant: Variant, mood: Mood) {
  const el = (name: string, attrs: Record<string, string | number>, ...kids: Element[]) => {
    const node = document.createElementNS(SVG_NS, name);
    for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
    node.append(...kids);
    return node;
  };
  const image = (a: { uri: string }, x: number, y: number, w: number, h: number) =>
    el("image", { href: a.uri, x, y, width: w, height: h, preserveAspectRatio: "none" });

  const rad = (ARM_ANGLE * Math.PI) / 180;
  const width = skin.armWidth * mood.armWidthScale;
  const length = 100 * mood.armLengthInHands;
  const tuck = skin.armWidth * 0.25;
  const sx = skin.armAnchor.x - Math.sin(rad) * tuck;
  const sy = skin.armAnchor.y - Math.cos(rad) * tuck;
  const tileH = width * (variant.tile.height / variant.tile.width);
  const cuffH = variant.cuff ? width * (variant.cuff.height / variant.cuff.width) : 0;
  const id = `sleeve-${++sleeveId}`;

  // The strip hangs down from the hand end (y = 0): the cuff once, then the tile repeated.
  const defs = el("defs", {},
    el("pattern", { id: `${id}-tile`, patternUnits: "userSpaceOnUse", x: -width / 2, y: cuffH, width, height: tileH },
      image(variant.tile, 0, 0, width, tileH)));
  const strip = el("g", { transform: `translate(${sx} ${sy}) rotate(${-ARM_ANGLE})`, opacity: mood.armOpacity });
  if (variant.tint) {
    defs.append(el("filter", { id: `${id}-tint`, x: 0, y: 0, width: 1, height: 1 },
      el("feFlood", { "flood-color": variant.tint }),
      el("feComposite", { in2: "SourceGraphic", operator: "in" })));
    strip.setAttribute("filter", `url(#${id}-tint)`);
  }
  if (skin.fade) {
    defs.append(
      el("linearGradient", { id: `${id}-fade`, gradientUnits: "userSpaceOnUse", x1: 0, y1: 0, x2: 0, y2: length },
        el("stop", { offset: 0, "stop-color": "#fff" }),
        el("stop", { offset: mood.armOpaqueFraction, "stop-color": "#fff" }),
        el("stop", { offset: 1, "stop-color": "#000" })),
      el("mask", { id: `${id}-mask`, maskUnits: "userSpaceOnUse", x: -width, y: -1, width: width * 2, height: length + 2 },
        el("rect", { x: -width, y: -1, width: width * 2, height: length + 2, fill: `url(#${id}-fade)` })));
  }
  const pieces = el("g", skin.fade ? { mask: `url(#${id}-mask)` } : {});
  if (variant.cuff) pieces.append(image(variant.cuff, -width / 2, 0, width, cuffH));
  pieces.append(el("rect", { x: -width / 2, y: cuffH, width, height: length - cuffH, fill: `url(#${id}-tile)` }));
  strip.append(pieces);

  svg.replaceChildren(defs, strip, image(variant.idle, 0, 0, 100, 100));
}

const stage = document.querySelector<HTMLElement>("[data-stage]");
const hand = stage?.querySelector<HTMLElement>(".hand");
const hint = document.querySelector<HTMLElement>("[data-streak]");
const reduced = matchMedia("(prefers-reduced-motion: reduce)");

if (stage && hand) {
  const body = hand.querySelector<HTMLElement>(".hand-body")!;
  const artSvg = hand.querySelector<SVGSVGElement>("[data-hand-art]")!;
  const controls = document.querySelector<HTMLElement>("[data-demo-controls]");
  const pick = <T extends HTMLElement>(name: string) => controls?.querySelector<T>(`[data-control="${name}"]`) ?? null;
  const skinSelect = pick<HTMLSelectElement>("skin");
  const colorSelect = pick<HTMLSelectElement>("color");
  const sizeInput = pick<HTMLInputElement>("size");
  const moodInput = pick<HTMLInputElement>("mood");
  const sizeOut = pick<HTMLOutputElement>("size-out");
  const moodOut = pick<HTMLOutputElement>("mood-out");
  const moodNames = (controls?.dataset.moods ?? "").split("|");

  let skin = SKINS[0];
  let variant = skin.variants[0];
  let mood = MOODS[DEFAULT_MOOD];
  let effectSlot = 0;

  const fillColors = () => {
    if (!colorSelect) return;
    colorSelect.replaceChildren(...skin.variants.map((v, i) => new Option(colorSelect.dataset[`c${v.name.toLowerCase()}`] ?? v.name, String(i))));
  };
  const apply = () => {
    skin = SKINS.find((s) => s.id === skinSelect?.value) ?? SKINS[0];
    variant = skin.variants[Number(colorSelect?.value)] ?? skin.variants[0];
    mood = MOODS[Number(moodInput?.value ?? DEFAULT_MOOD)] ?? MOODS[DEFAULT_MOOD];
    const px = handPixels(Number(sizeInput?.value ?? 1));
    hand.style.width = hand.style.height = `${px}px`;
    if (sizeOut) sizeOut.textContent = `${sizeInput?.value ?? 1}×`;
    if (moodOut) moodOut.textContent = moodNames[Number(moodInput?.value ?? DEFAULT_MOOD)] ?? "";
    drawHand(artSvg, skin, variant, mood);
    place();
  };
  skinSelect?.addEventListener("change", () => {
    skin = SKINS.find((s) => s.id === skinSelect.value) ?? SKINS[0];
    fillColors();
    apply();
  });
  [colorSelect, sizeInput, moodInput].forEach((c) => c?.addEventListener("input", apply));
  let x = 0;
  let y = 0;
  let queued = false;
  let streak = 0;
  let lastClick = 0;
  let hideTimer = 0;

  const size = () => hand.offsetWidth;

  const place = () => {
    queued = false;
    const s = size();
    hand.style.transform = `translate3d(${x - (s * skin.hotspot.x) / 100}px, ${y - (s * skin.hotspot.y) / 100}px, 0)`;
  };
  const schedule = () => {
    if (!queued) {
      queued = true;
      requestAnimationFrame(place);
    }
  };
  const moveTo = (e: PointerEvent) => {
    const r = stage.getBoundingClientRect();
    x = e.clientX - r.left;
    y = e.clientY - r.top;
    schedule();
  };

  const enable = () => {
    stage.classList.toggle("is-live", !reduced.matches);
    if (reduced.matches) {
      // Static: park the hand in the middle, no following, no effects.
      const r = stage.getBoundingClientRect();
      x = r.width * 0.5;
      y = r.height * 0.4;
      place();
      hand.classList.add("is-visible");
    }
  };
  fillColors();
  apply();
  enable();
  reduced.addEventListener("change", enable);

  // Effects grow with the mood, like OverlayController (burstRadius relative to the default mood).
  const moodRatio = () => mood.burstRadius / MOODS[DEFAULT_MOOD].burstRadius;

  // The design's own click art (cat, magic): one piece per burst, in turn, scattered and spun.
  const playArt = () => {
    const c = skin.click;
    const a = c.art[effectSlot++ % c.art.length];
    const s = size() * c.size * moodRatio();
    const rnd = (lo: number, hi: number) => lo + Math.random() * (hi - lo);
    const spread = c.scatter * size();
    const img = document.createElement("img");
    img.src = a.uri;
    img.alt = "";
    img.className = "click-art";
    img.style.width = img.style.height = `${s}px`;
    img.style.left = `${x + rnd(-spread, spread) - s / 2}px`;
    img.style.top = `${y + rnd(-spread, spread) - s / 2}px`;
    stage.insertBefore(img, hand);
    const turn = rnd(-c.rotation, c.rotation);
    img.animate(
      [
        { scale: c.from, rotate: "0deg", opacity: 1 },
        { scale: c.to, rotate: `${turn}deg`, opacity: 0 },
      ],
      { duration: c.duration * 1000, easing: "ease-out", fill: "forwards" },
    ).finished.finally(() => img.remove());
  };

  const burst = () => {
    if (!skin.click.classic) return playArt();
    const big = true;
    const n = mood.burstRays;
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "-50 -50 100 100");
    svg.setAttribute("class", "burst" + (big ? " burst-big" : ""));
    const px = size() * skin.click.size * moodRatio();
    svg.style.width = svg.style.height = `${px}px`;
    svg.style.margin = `${-px / 2}px 0 0 ${-px / 2}px`;
    svg.style.setProperty("--burst-weight", String(mood.burstWeight));
    svg.style.left = `${x}px`;
    svg.style.top = `${y}px`;
    let d = "";
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + (big ? 0.2 : 0);
      const r1 = 18;
      const r2 = big && i % 2 === 0 ? 46 : 36;
      d += `M${(Math.cos(a) * r1).toFixed(1)} ${(Math.sin(a) * r1).toFixed(1)}L${(Math.cos(a) * r2).toFixed(1)} ${(Math.sin(a) * r2).toFixed(1)}`;
    }
    // Every click turns and resizes the splash and drops the star somewhere new (like the app).
    const rnd = (a: number, b: number) => a + Math.random() * (b - a);
    const rays = document.createElementNS("http://www.w3.org/2000/svg", "path");
    rays.setAttribute("d", d);
    rays.setAttribute("transform", `rotate(${rnd(0, 360).toFixed(0)}) scale(${rnd(0.8, 1.2).toFixed(2)} ${rnd(0.8, 1.2).toFixed(2)})`);
    svg.append(rays);
    if (big) {
      const star = document.createElementNS("http://www.w3.org/2000/svg", "path");
      let sd = "";
      for (let i = 0; i < 10; i++) {
        const a = (i / 10) * Math.PI * 2 - Math.PI / 2;
        const r = i % 2 ? 7 : 15;
        sd += `${i ? "L" : "M"}${(Math.cos(a) * r).toFixed(1)} ${(Math.sin(a) * r).toFixed(1)}`;
      }
      star.setAttribute("d", sd + "Z");
      star.setAttribute("class", "burst-star");
      star.setAttribute("transform", `translate(${rnd(-12, 12).toFixed(1)} ${rnd(-12, 12).toFixed(1)}) rotate(${rnd(-35, 35).toFixed(0)}) scale(${rnd(0.85, 1.15).toFixed(2)})`);
      svg.append(star);
    }
    stage.insertBefore(svg, hand); // behind the hand, like the app
    setTimeout(() => svg.remove(), 450);
  };

  const frames = (steps: number[], shake: boolean): Keyframe[] => {
    const d = size() * HOP_DIST * (mood.jabDistance / MOODS[DEFAULT_MOOD].jabDistance);
    return steps.map((v, i) => {
      const side = shake ? (i % 2 ? 1 : -1) * (i === 0 || i === steps.length - 1 ? 0 : SHAKE * size()) : 0;
      return {
        translate: `${AXIS.x * v * d + SIDE.x * side}px ${AXIS.y * v * d + SIDE.y * side}px`,
        easing: shake ? "ease-out" : HOP_EASING[i] ?? "linear",
        ...(shake ? {} : { offset: HOP_TIMES[i] }),
      };
    });
  };
  const hop = () =>
    body.animate(frames(HOP, false), { duration: HOP_MS });
  const jab = (el: HTMLElement, delay = 0) =>
    el.animate(frames(JAB, true), { duration: JAB_MS, delay, fill: "backwards" });

  // Two trailing copies at constant opacity, 45 ms apart; they all go when the jab ends (no fade).
  const trail = () => {
    TRAIL_ALPHA.forEach((alpha, i) => {
      const g = document.createElement("div");
      g.className = "hand-ghost";
      g.style.transform = hand.style.transform;
      g.style.width = hand.style.width;
      g.style.height = hand.style.height;
      g.style.opacity = String(alpha);
      const copy = body.cloneNode(true) as HTMLElement;
      g.append(copy);
      stage.insertBefore(g, hand);
      jab(copy, TRAIL_MS * (i + 1));
      setTimeout(() => g.remove(), JAB_MS + TRAIL_MS * TRAIL_ALPHA.length + 50);
    });
  };

  stage.addEventListener("pointerenter", (e) => {
    if (reduced.matches) return;
    clearTimeout(hideTimer);
    moveTo(e);
    hand.classList.add("is-visible");
  });
  stage.addEventListener("pointermove", (e) => {
    if (reduced.matches) return;
    moveTo(e);
    hand.classList.add("is-visible");
  });
  stage.addEventListener("pointerleave", (e) => {
    if (reduced.matches) return;
    // Touch keeps the hand where the finger lifted, remembering its position.
    if (e.pointerType === "mouse") hand.classList.remove("is-visible");
  });

  stage.addEventListener("pointerdown", (e) => {
    if (reduced.matches) return;
    clearTimeout(hideTimer);
    moveTo(e);
    place();
    hand.classList.add("is-visible");

    const now = performance.now();
    streak = now - lastClick < STREAK_MS ? streak + 1 : 1;
    lastClick = now;

    body.getAnimations().forEach((a) => a.cancel());
    if (streak >= 3) {
      jab(body);
      trail();
      burst();
    } else {
      hop();
    }
    if (hint) {
      hint.textContent = streak >= 3 ? `×${streak} — ${stage.dataset.jab ?? "jab!"}` : `×${streak}`;
      hint.classList.toggle("hot", streak >= 3);
    }
  });
}

// Copy buttons
document.querySelectorAll<HTMLButtonElement>("[data-copy]").forEach((btn) => {
  const status = btn.parentElement?.querySelector<HTMLElement>("[data-copy-status]");
  btn.addEventListener("click", async () => {
    const text = btn.dataset.copy ?? "";
    let ok = false;
    try {
      await navigator.clipboard.writeText(text);
      ok = true;
    } catch {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.append(ta);
      ta.select();
      ok = document.execCommand("copy");
      ta.remove();
    }
    // Copy comes from the page dictionary (data-* on the button) so it follows the locale.
    const label = btn.querySelector<HTMLElement>("[data-copy-label]");
    const idle = btn.dataset.label ?? "Copy";
    if (label) label.textContent = ok ? (btn.dataset.copied ?? "Copied!") : (btn.dataset.fallback ?? "Press ⌘C");
    if (status) status.textContent = (ok ? btn.dataset.statusOk : btn.dataset.statusFail) ?? "";
    setTimeout(() => {
      if (label) label.textContent = idle;
      if (status) status.textContent = "";
    }, 2000);
  });
});
