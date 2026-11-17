// Designs, moods and sizes for the live demo, mirrored from the app so the page shows what you get.
// The SVGs are read straight from Resources/Skins (one source of truth with the app); the numbers
// mirror each skin.json, Sources/ManitaCore/Mood.swift and Preferences.swift.

const files = import.meta.glob<string>("../../../Resources/Skins/*/*.svg", {
  query: "?raw",
  import: "default",
  eager: true,
});

/** A skin's SVG as a data URI plus its viewBox size. */
export interface Art {
  uri: string;
  width: number;
  height: number;
}

const art = (skin: string, file: string): Art => {
  const raw = files[`../../../Resources/Skins/${skin}/${file}`];
  if (!raw) throw new Error(`Missing skin art: ${skin}/${file}`);
  const box = raw.match(/viewBox="([^"]+)"/)?.[1].trim().split(/[\s,]+/).map(Number) ?? [0, 0, 100, 100];
  return { uri: `data:image/svg+xml;charset=utf-8,${encodeURIComponent(raw)}`, width: box[2], height: box[3] };
};

export interface Variant {
  name: string;
  idle: Art;
  tile: Art;
  cuff?: Art;
  /** Fill colour for designs whose sleeve is a tinted silhouette. */
  tint?: string;
}

export interface Skin {
  id: string;
  name: string;
  /** Points in the 100-unit artwork space. */
  hotspot: { x: number; y: number };
  armAnchor: { x: number; y: number };
  armWidth: number;
  fade: boolean;
  /** "classic" draws the procedural rays + star; otherwise the design's click art rotates per click. */
  click: { classic: boolean; art: Art[]; size: number; from: number; to: number; duration: number; rotation: number; scatter: number };
  variants: Variant[];
}

const cartoonIdle = art("cartoon", "idle.svg");
const cartoonSleeve = art("cartoon", "sleeve.svg");
const wandIdle = art("magic-wand", "idle.svg");
const wandTip = art("magic-wand", "wand-tip.svg");

export const SKINS: Skin[] = [
  {
    id: "cartoon",
    name: "Cartoon",
    hotspot: { x: 35, y: 6 },
    armAnchor: { x: 60.3, y: 87.2 },
    armWidth: 30,
    fade: true,
    click: { classic: true, art: [], size: 1.6, from: 0.6, to: 2.15, duration: 0.4, rotation: 35, scatter: 0.4 },
    variants: [
      { name: "Dark", idle: cartoonIdle, tile: cartoonSleeve, tint: "#111111" },
      { name: "Light", idle: cartoonIdle, tile: cartoonSleeve, tint: "#F2F2F2D9" },
    ],
  },
  {
    id: "cat-paw",
    name: "Cat Paw",
    hotspot: { x: 31.4, y: 7.8 },
    armAnchor: { x: 60.9, y: 80.1 },
    armWidth: 34,
    fade: true,
    click: {
      classic: false,
      art: ["paw-prints.svg", "hearts.svg", "scratch.svg"].map((f) => art("cat-paw", f)),
      size: 1.6, from: 0.5, to: 1.3, duration: 0.45, rotation: 30, scatter: 0.35,
    },
    variants: (["Black", "Tabby", "Gray"] as const).map((name) => ({
      name,
      idle: art("cat-paw", `paw-${name.toLowerCase()}.svg`),
      tile: art("cat-paw", `leg-${name.toLowerCase()}.svg`),
    })),
  },
  {
    id: "magic-wand",
    name: "Magic Wand",
    hotspot: { x: 50, y: 46 },
    armAnchor: { x: 56, y: 62 },
    armWidth: 22,
    fade: false,
    click: {
      classic: false,
      art: ["sparkles.svg", "stardust.svg", "spiral.svg", "rune-circle.svg"].map((f) => art("magic-wand", f)),
      size: 1.7, from: 0.5, to: 1.35, duration: 0.5, rotation: 40, scatter: 0.3,
    },
    variants: [
      { name: "Classic", idle: wandIdle, tile: art("magic-wand", "wand-black.svg"), cuff: wandTip },
      { name: "Purple", idle: wandIdle, tile: art("magic-wand", "wand-purple.svg"), cuff: wandTip },
      { name: "Gold", idle: wandIdle, tile: art("magic-wand", "wand-gold.svg"), cuff: wandTip },
    ],
  },
];

/** Mood.swift, levels 0 (Subtle) to 3 (Look at me!). */
export const MOODS = [
  { armWidthScale: 0.7, armLengthInHands: 3, armOpacity: 0.55, armOpaqueFraction: 0.05, jabDistance: 0.08, burstRadius: 0.6, burstRays: 6, burstWeight: 0.8 },
  { armWidthScale: 0.9, armLengthInHands: 6, armOpacity: 0.85, armOpaqueFraction: 0.45, jabDistance: 0.16, burstRadius: 0.8, burstRays: 9, burstWeight: 1 },
  { armWidthScale: 1.05, armLengthInHands: 10, armOpacity: 1, armOpaqueFraction: 0.7, jabDistance: 0.26, burstRadius: 1.05, burstRays: 12, burstWeight: 1.25 },
  { armWidthScale: 1.2, armLengthInHands: 16, armOpacity: 1, armOpaqueFraction: 0.85, jabDistance: 0.38, burstRadius: 1.35, burstRays: 16, burstWeight: 1.6 },
];
export type Mood = (typeof MOODS)[number];
export const DEFAULT_MOOD = 1;

/** Preferences.swift: sizes 1–8 are internal scales 5–12, 13 pt each (HandArtwork.svgPointsPerScale). */
export const SIZES = [1, 2, 3, 4, 5, 6, 7, 8];
export const handPixels = (size: number) => (size + 4) * 13;
