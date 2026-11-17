// Live demo: the cartoon hand follows the pointer inside the stage.
// Mirrors the app: every click makes the hand + sleeve hop up-left along the
// finger axis and spring back (the artwork never changes). From the 3rd rapid
// click (< 450 ms apart) the hand jabs and shakes, leaves two trailing
// copies and a burst plays behind it.

const STREAK_MS = 450;
const HOT_X = 0.35; // hotspot from skin.json, as a fraction of the hand box
const HOT_Y = 0.06;
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
const HOP_DIST = 0.12; // of hand size
const SHAKE = 0.07; // sideways, of hand size

const stage = document.querySelector<HTMLElement>("[data-stage]");
const hand = stage?.querySelector<HTMLElement>(".hand");
const hint = document.querySelector<HTMLElement>("[data-streak]");
const reduced = matchMedia("(prefers-reduced-motion: reduce)");

if (stage && hand) {
  const body = hand.querySelector<HTMLElement>(".hand-body")!;
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
    hand.style.transform = `translate3d(${x - s * HOT_X}px, ${y - s * HOT_Y}px, 0)`;
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
  enable();
  reduced.addEventListener("change", enable);

  const burst = () => {
    const big = true;
    const n = 12;
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "-50 -50 100 100");
    svg.setAttribute("class", "burst" + (big ? " burst-big" : ""));
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
    const d = size() * HOP_DIST;
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
    // Touch taps keep the hand a moment so the effect is seen.
    hideTimer = window.setTimeout(
      () => hand.classList.remove("is-visible"),
      e.pointerType === "mouse" ? 0 : 700,
    );
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
    if (e.pointerType !== "mouse") {
      hideTimer = window.setTimeout(() => hand.classList.remove("is-visible"), 900);
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
