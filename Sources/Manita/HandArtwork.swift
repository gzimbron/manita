import AppKit
import ManitaCore
import ManitaSkins

/// A skin rendered for the screen, independent of how it was drawn.
struct HandArtwork {
    var idle: CGImage
    var pressed: CGImage
    /// Size of the hand in points.
    var size: CGSize
    /// Click point, in points from the top-left of the hand.
    var hotspot: CGPoint
    /// Where the arm attaches, in points from the top-left of the hand.
    var armAnchor: CGPoint
    /// Arm thickness in points.
    var armWidth: CGFloat
    /// Points per art unit; used to size the click burst.
    var unit: CGFloat
    /// Color of the click burst.
    var outline: CGColor
    /// Color of the wand.
    var wandColor: CGColor
    /// How the wand is drawn (`wand` in `skin.json`).
    var wand: WandConfig
    /// The click effects the design asks for (`click` in `skin.json`).
    var click: ClickConfig
    /// Backing scale of the images (layer `contentsScale`).
    var contentsScale: CGFloat
    /// Nearest-neighbor magnification for pixel art.
    var isPixelArt: Bool

    /// Points drawn for the longer side of an SVG viewBox, per step of the Size setting.
    static let svgPointsPerScale: CGFloat = 13
    static let defaultArmColor = RGBA(r: 0x11, g: 0x11, b: 0x11)
    /// Light metal gray for a `stick` wand that names no color.
    static let defaultStickColor = RGBA(r: 0xC8, g: 0xCC, b: 0xD2)

    static func render(_ skin: Skin, scale: Int, backingScale: CGFloat = 2) -> HandArtwork? {
        skin.svg == nil ? renderPixels(skin, scale: scale) : renderSVG(skin, scale: scale, backingScale: backingScale)
    }

    private static func renderPixels(_ skin: Skin, scale: Int) -> HandArtwork? {
        guard let idle = try? skin.image(for: .idle).cgImage(),
              let pressed = try? skin.image(for: .pressed).cgImage()
        else { return nil }
        let s = CGFloat(scale)
        let outline = skin.palette["#"].flatMap(RGBA.init(hex:)).map(\.cgColor) ?? NSColor.black.cgColor
        let size = CGSize(width: CGFloat(idle.width) * s, height: CGFloat(idle.height) * s)
        return HandArtwork(
            idle: idle, pressed: pressed, size: size,
            hotspot: CGPoint(x: (CGFloat(skin.hotspot.x) + 0.5) * s, y: (CGFloat(skin.hotspot.y) + 0.5) * s),
            armAnchor: CGPoint(x: size.width * 0.55, y: size.height - s),
            armWidth: size.width * 0.28,
            unit: s / 2, outline: outline, wandColor: outline, wand: WandConfig(), click: ClickConfig(),
            contentsScale: 1, isPixelArt: true
        )
    }

    private static func renderSVG(_ skin: Skin, scale: Int, backingScale: CGFloat) -> HandArtwork? {
        guard (try? skin.validate()) != nil, let box = skin.svgViewBox, let hotspot = skin.svgHotspot,
              let idleData = skin.svgData[.idle]
        else { return nil }
        let unit = CGFloat(scale) * svgPointsPerScale / CGFloat(max(box.width, box.height))
        let size = CGSize(width: CGFloat(box.width) * unit, height: CGFloat(box.height) * unit)
        guard let idle = rasterize(idleData, size: size, backingScale: backingScale),
              let pressed = rasterize(skin.svgData[.pressed] ?? idleData, size: size, backingScale: backingScale)
        else { return nil }
        func point(_ p: SVGPoint) -> CGPoint {
            CGPoint(x: CGFloat(p.x - box.x) * unit, y: CGFloat(p.y - box.y) * unit)
        }
        let anchor = skin.svgArmAnchor ?? SVGPoint(x: box.x + box.width / 2, y: box.y + box.height)
        let wandColor = skin.resolvedWandColor.flatMap(RGBA.init(hex:))
            ?? (skin.wand.style == .stick ? defaultStickColor : defaultArmColor)
        let clickColor = skin.resolvedClickColor.flatMap(RGBA.init(hex:)) ?? wandColor
        return HandArtwork(
            idle: idle, pressed: pressed, size: size,
            hotspot: point(hotspot), armAnchor: point(anchor),
            armWidth: CGFloat(skin.resolvedArmWidth ?? box.width * 0.3) * unit,
            unit: CGFloat(scale) * 0.5, outline: clickColor.cgColor, wandColor: wandColor.cgColor,
            wand: skin.wand, click: skin.click, contentsScale: backingScale, isPixelArt: false
        )
    }

    /// Draws SVG data (via `NSImage`, which renders SVG natively) into a bitmap of `size` points.
    private static func rasterize(_ data: Data, size: CGSize, backingScale: CGFloat) -> CGImage? {
        guard let image = NSImage(data: data) else { return nil }
        let width = Int((size.width * backingScale).rounded(.up))
        let height = Int((size.height * backingScale).rounded(.up))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

extension SkinRegistry {
    /// The designs available without a user folder: only the bundled Glove (user designs are added on top).
    static func appDefault() -> SkinRegistry {
        var registry = SkinRegistry(skins: [])
        for folder in BuiltInSkins.folders {
            do {
                try registry.register(manifestAt: folder)
            } catch {
                NSLog("Manita: bundled design %@ failed to load: %@", folder.lastPathComponent, String(describing: error))
            }
        }
        return registry
    }
}

extension RGBA {
    var cgColor: CGColor {
        CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
