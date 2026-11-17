import AppKit
import ManitaCore

/// Renders designs into PNGs without showing any window: the idle and pressed frames
/// side by side (`run`), or the whole on-screen pointer for one mood (`runPointer`).
@MainActor
enum PreviewRenderer {
    /// Arguments: `<out.png> [skin id, design folder or .json] [scale]`. Returns an exit code.
    static func run(_ args: [String]) -> Int32 {
        func fail(_ message: String) -> Int32 {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        }
        let out = URL(fileURLWithPath: args[0])
        let skinArg = args.count > 1 ? args[1] : Skin.cartoon.id
        let range = Preferences.displaySizeRange
        let scaleArg = args.count > 2 ? args[2] : "2"
        guard let scale = Int(scaleArg).flatMap(Preferences.scale(forDisplaySize:)) else {
            return fail("Invalid size '\(scaleArg)': expected an integer from \(range.lowerBound) to \(range.upperBound)")
        }

        var registry = SkinRegistry.appDefault()
        var skin: Skin
        var isFolder: ObjCBool = false
        let isPath = FileManager.default.fileExists(atPath: skinArg, isDirectory: &isFolder) && isFolder.boolValue
        if skinArg.hasSuffix(".json") || isPath {
            do {
                skin = try registry.register(manifestAt: URL(fileURLWithPath: skinArg))
            } catch {
                return fail("Invalid design: \(error)")
            }
        } else if let known = registry.skins.first(where: { $0.id == skinArg }) {
            skin = known
        } else {
            let ids = registry.skins.map(\.id).joined(separator: ", ")
            return fail("Unknown design '\(skinArg)'. Built-in designs: \(ids), or pass a design folder or .json file")
        }
        guard let art = HandArtwork.render(skin, scale: scale) else { return fail("Cannot render '\(skinArg)'") }

        let pad = art.size.width * 0.3
        let size = CGSize(width: art.size.width * 2 + pad * 3, height: art.size.height + pad * 2)
        let px = art.contentsScale
        guard let ctx = CGContext(data: nil, width: Int(size.width * px), height: Int(size.height * px),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.scaleBy(x: px, y: px)
        ctx.interpolationQuality = art.isPixelArt ? .none : .high
        ctx.setFillColor(CGColor(red: 1, green: 0.36, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        for (i, image) in [art.idle, art.pressed].enumerated() {
            let x = pad + CGFloat(i) * (art.size.width + pad)
            ctx.draw(image, in: CGRect(origin: CGPoint(x: x, y: pad), size: art.size))
        }
        return write(ctx, to: out)
    }

    /// Arguments: `<out.png> [skin id] [scale] [mood] [light|dark]`. Draws the whole pointer the
    /// way it looks on screen (sleeve, hand and a click burst) for one mood. The design is a bundled id, a design folder or a `.json`. Returns an exit code.
    static func runPointer(_ args: [String]) -> Int32 {
        func fail(_ message: String) -> Int32 {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            return 1
        }
        var registry = SkinRegistry.appDefault()
        let skinArg = args.count > 1 ? args[1] : Skin.cartoon.id
        let skin: Skin
        var isFolder: ObjCBool = false
        if skinArg.hasSuffix(".json") || (FileManager.default.fileExists(atPath: skinArg, isDirectory: &isFolder) && isFolder.boolValue) {
            do {
                skin = try registry.register(manifestAt: URL(fileURLWithPath: skinArg))
            } catch {
                return fail("Invalid design: \(error)")
            }
        } else if let known = registry.skins.first(where: { $0.id == skinArg }) {
            skin = known
        } else {
            return fail("Unknown design '\(skinArg)'. Built-in designs: \(registry.skins.map(\.id).joined(separator: ", ")), or pass a design folder or .json file")
        }
        let range = Preferences.displaySizeRange
        let scaleArg = args.count > 2 ? args[2] : String(Preferences.displaySize(forScale: Preferences.default.scale))
        guard let scale = Int(scaleArg).flatMap(Preferences.scale(forDisplaySize:)) else {
            return fail("Invalid size '\(scaleArg)': expected an integer from \(range.lowerBound) to \(range.upperBound)")
        }
        let moodArg = args.count > 3 ? args[3] : String(Mood.default)
        guard let mood = Int(moodArg), Mood.range.contains(mood) else {
            return fail("Invalid mood '\(moodArg)': expected an integer from \(Mood.range.lowerBound) to \(Mood.range.upperBound)")
        }
        let appearance = args.count > 4 ? args[4] : "light"
        guard ["light", "dark"].contains(appearance) else {
            return fail("Invalid appearance '\(appearance)': expected light or dark")
        }
        let isDark = appearance == "dark"

        let overlay = OverlayController()
        overlay.configure(skin: skin, scale: scale, showArm: true, mood: Mood.style(mood),
                          color: PointerColor.automatic.resolved(systemIsDark: isDark)?.cgColor)
        let layout = overlay.previewLayout
        // Extra room above and left of the hotspot for the burst; long sleeves are cut at the bottom.
        let pad = CGFloat(scale) * HandArtwork.svgPointsPerScale * 1.2
        let size = CGSize(width: min(layout.size.width + pad, 700), height: min(layout.size.height + pad, 700))
        let px: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(size.width * px), height: Int(size.height * px),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        ctx.scaleBy(x: px, y: px)
        ctx.setFillColor(isDark ? CGColor(gray: 0.18, alpha: 1) : CGColor(red: 1, green: 0.36, blue: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        overlay.drawPreview(in: ctx, hotspot: CGPoint(x: layout.hotspot.x + pad,
                                                      y: size.height - (layout.size.height - layout.hotspot.y) - pad))
        return write(ctx, to: URL(fileURLWithPath: args[0]))
    }

    private static func write(_ ctx: CGContext, to out: URL) -> Int32 {
        guard let image = ctx.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return 1 }
        do {
            try png.write(to: out)
        } catch {
            FileHandle.standardError.write(Data("Cannot write \(out.path): \(error)\n".utf8))
            return 1
        }
        print("Wrote \(out.path)")
        return 0
    }
}
