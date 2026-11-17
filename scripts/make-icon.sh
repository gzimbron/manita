#!/usr/bin/env bash
# Renders Resources/Icon/icon.svg into the iconset, Manita.icns and the web assets.
# Needs only the Xcode command-line tools (a tiny Swift/AppKit helper rasterizes the SVG) and iconutil.
# Usage: scripts/make-icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/Resources/Icon"
WEB="$ICON/web"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

cat > "$SCRATCH/render.swift" <<'SWIFT'
import AppKit

// render svg <svg> <out.png> <size>
// render og  <svg> <out.png> <width> <height>
let a = CommandLine.arguments

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(_ rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

guard a.count >= 5, let img = NSImage(contentsOfFile: a[2]) else { fatalError("usage") }

if a[1] == "svg" {
    let s = Int(a[4])!
    let rep = bitmap(s, s)
    draw(rep) { img.draw(in: NSRect(x: 0, y: 0, width: s, height: s)) }
    save(rep, a[3])
} else {
    let w = Int(a[4])!, h = Int(a[5])!
    let rep = bitmap(w, h)
    draw(rep) {
        func c(_ hex: Int, _ al: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: al)
        }
        let full = NSRect(x: 0, y: 0, width: w, height: h)
        c(0xF1E4C4).setFill(); full.fill()
        // soft vignette
        NSGradient(colors: [c(0x5A4630, 0), c(0x5A4630, 0), c(0x5A4630, 0.28)],
                   atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
            .draw(in: full, relativeCenterPosition: .zero)
        // double rule frame
        c(0x1C1712).setStroke()
        let outer = NSBezierPath(rect: full.insetBy(dx: 22, dy: 22)); outer.lineWidth = 4; outer.stroke()
        let inner = NSBezierPath(rect: full.insetBy(dx: 34, dy: 34)); inner.lineWidth = 1.5; inner.stroke()

        let side = CGFloat(h) * 0.62
        let ix: CGFloat = 90
        img.draw(in: NSRect(x: ix - side * 0.1, y: (CGFloat(h) - side) / 2, width: side, height: side))
        let x = ix + side * 0.8 + 30
        func text(_ str: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
            NSAttributedString(string: str, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        }
        let serif = NSFontManager.shared.convert(NSFont(name: "Georgia-BoldItalic", size: 160)
            ?? NSFont.systemFont(ofSize: 160, weight: .heavy), toHaveTrait: .italicFontMask)
        let ty = CGFloat(h) / 2 - 72
        text("Manita", serif, c(0xB8322A)).draw(at: NSPoint(x: x + 8, y: ty - 8))
        text("Manita", serif, c(0x1C1712)).draw(at: NSPoint(x: x, y: ty))
        let sans = NSFont(name: "Futura-Bold", size: 27) ?? NSFont.systemFont(ofSize: 27, weight: .heavy)
        text("A CARTOON HAND FOR YOUR POINTER", sans, c(0x4A3F33), kern: 4.5)
            .draw(at: NSPoint(x: x + 6, y: ty - 50))
        text("★  NOW SHOWING ON YOUR MAC  ★", NSFont(name: "Futura-Bold", size: 19) ?? sans, c(0xB8322A), kern: 5)
            .draw(at: NSPoint(x: x + 6, y: ty + 185))
    }
    save(rep, a[3])
}
SWIFT
swiftc -O "$SCRATCH/render.swift" -o "$SCRATCH/render" 2>/dev/null
render() { "$SCRATCH/render" svg "$1" "$2" "$3"; }

# macOS iconset -> .icns
SET="$SCRATCH/Manita.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
    render "$ICON/icon.svg" "$SET/icon_${s}x${s}.png" "$s"
    render "$ICON/icon.svg" "$SET/icon_${s}x${s}@2x.png" "$((s * 2))"
done
iconutil -c icns "$SET" -o "$ICON/Manita.icns"

# Web favicon: hand-drawn source of truth at Resources/Icon/web/favicon.svg (kept as is).

# Web assets
mkdir -p "$WEB"
render "$ICON/icon.svg" "$WEB/apple-touch-icon.png" 180
render "$ICON/icon.svg" "$WEB/icon-512.png" 512
"$SCRATCH/render" og "$ICON/icon.svg" "$WEB/og.png" 1200 630

echo "Wrote $ICON/Manita.icns and web assets in $WEB"
