// English copy (default locale). `es.ts` must have exactly the same keys: it is typed as `Dict`.
// "{P}" and "{T}" inside feature texts become inline key caps (⌃⌥P / ⌃⌥T).
// Keys ending in `Html` are trusted markup rendered with set:html.
export const en = {
  htmlLang: "en",
  ogLocale: "en_US",
  langName: "English",
  title: "Manita — A cartoon hand for your pointer",
  description:
    "Manita is a free, open-source macOS menu bar app that turns your pointer into an old-cartoon gloved hand with a long sleeve, click bursts and a presentation mode.",
  ogImageAlt: "Manita: a cartoon glove as a mouse pointer",
  skip: "Skip to content",
  navLabel: "Main",
  langSwitchLabel: "Language",
  nav: { features: "Features", presentation: "Presentation", install: "Install", github: "GitHub" },
  kicker: "★ Now showing on your Mac ★",
  tagline: "A cartoon hand for your pointer",
  pitch:
    "A tiny macOS menu bar app that swaps your cursor for an old-cartoon gloved hand with a long sleeve, a click jab and a natural click sound.",
  copy: "Copy",
  copySr: " install command",
  copied: "Copied!",
  copyFallback: "Press ⌘C",
  copiedStatus: "Install command copied to clipboard",
  copyFailedStatus: "Copy failed, select the command and press Command C",
  download: "Download for macOS",
  toggleHand: "Show or hide the hand",
  note: "macOS 26 or later · Free & open source",
  iconAlt: "Manita app icon: a cartoon glove pointing, on cream paper",
  keyNames: { "⌃": "control", "⌥": "option", "⌘": "command", "⇧": "shift" } as Record<string, string>,
  demo: {
    title: "Try it right here",
    lede: "Move your pointer over the stage. Click to make the hand hop. Click three times fast to make it jab and shake.",
    hint: "Move here · click · click ×3 fast",
    jab: "jab!",
    design: "Design",
    color: "Color",
    size: "Size",
    mood: "Mood",
    moods: ["Subtle", "Default", "Lively", "Look at me!"],
    designs: { cartoon: "Cartoon", "cat-paw": "Cat Paw", "magic-wand": "Magic Wand" } as Record<string, string>,
    colors: { dark: "Dark", light: "Light", black: "Black", tabby: "Tabby", gray: "Gray", classic: "Classic", purple: "Purple", gold: "Gold" } as Record<string, string>,
    sr: "This is a decorative, mouse-driven demo; it has no keyboard interaction.",
  },
  featuresTitle: "Small hand, big personality",
  features: [
    { icon: "🎚️", title: "Pointer mood", text: "A four-stop slider from Subtle to Look at me! Wider sleeve, harder jabs, bigger bursts." },
    { icon: "💥", title: "Effects from click N", text: "Every click makes the hand hop and spring back. From the third rapid click it jabs, shakes and bursts." },
    { icon: "🎤", title: "Presentation mode", text: "{T} holds clicks back from every app, so you can call out details without advancing your slides." },
    { icon: "⌨️", title: "Global shortcuts", text: "{P} shows or hides the pointer, {T} toggles presentation mode. Both are customizable." },
    { icon: "🌗", title: "Dark mode color", text: "The sleeve is black on light desktops and translucent gray in Dark Mode, switching with macOS." },
    { icon: "🖥️", title: "Works across displays", text: "Follows the pointer across every app, Space and full-screen window." },
    { icon: "🎨", title: "Custom designs", text: "Drop a folder with a skin.json and a couple of SVGs into your Skins folder and reload." },
  ],
  present: {
    title: "Presentation mode",
    lede: "Pointing at things during a demo shouldn't press them. Turn it on and Manita keeps animating every click while holding the click back from every app.",
    checks: [
      "Nothing gets pressed and your slides don't advance.",
      "Dragging only moves the pointer; scrolling and the keyboard keep working.",
      "{T} is the only way out, and a notice reminds you of it.",
      "Never restored on launch: Manita always starts with working clicks.",
    ],
    toggle: "Presentation mode on/off",
  },
  install: {
    title: "Get Manita",
    homebrew: "Homebrew",
    directTitle: "Direct download",
    directHtml: "Grab the latest <code>.zip</code> from GitHub Releases, unzip it and drag Manita to Applications.",
    firstRunHtml:
      "<strong>First run:</strong> Manita lives in the menu bar (no Dock icon). Accessibility permission is only needed for presentation mode; grant it in System Settings → Privacy &amp; Security → Accessibility when macOS asks.",
  },
  footer: { github: "GitHub", license: "MIT license", madeBy: "Made by Gustavo Zimbrón" },
};

export type Dict = typeof en;
