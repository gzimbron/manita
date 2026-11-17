import Foundation

/// An 8-bit RGBA color.
public struct RGBA: Equatable, Hashable, Sendable {
    public var r, g, b, a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA`.
    public init?(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt32(text, radix: 16) else { return nil }
        if text.count == 6 {
            self.init(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
        } else {
            self.init(r: UInt8(value >> 24 & 0xFF), g: UInt8(value >> 16 & 0xFF),
                      b: UInt8(value >> 8 & 0xFF), a: UInt8(value & 0xFF))
        }
    }
}

/// A rendered frame: row-major pixels, `nil` is transparent. Row 0 is the top.
public struct PixelImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [RGBA?]

    public func pixel(x: Int, y: Int) -> RGBA? { pixels[y * width + x] }
}

/// The animation states a skin can draw.
public enum FrameKind: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    /// Resting pointer.
    case idle
    /// Shown while the mouse button is held down. Falls back to `idle`.
    case pressed
}

public enum SkinError: Error, Equatable {
    case missingIdleFrame
    case emptyFrame(frame: FrameKind)
    case raggedRows(frame: FrameKind)
    case unknownSymbol(Character, frame: FrameKind)
    case invalidColor(String)
    case hotspotOutOfBounds
    case armAnchorOutOfBounds
    /// A `wand` value out of range.
    case invalidWand(String)
    /// A `click` value out of range.
    case invalidClick(String)
    /// `image(for:)` was called on an SVG skin.
    case notPixelArt
    /// An SVG file named by the manifest is not a plain file name ending in `.svg`.
    case invalidSVGPath(String)
    /// An SVG file named by the manifest was not loaded or does not exist.
    case missingSVGFile(String)
    /// The file is not an SVG with a usable `viewBox` (or `width`/`height`).
    case invalidSVG(String)
    /// `pressed` and `idle` do not share the same viewBox.
    case viewBoxMismatch
}

/// The SVG files of an SVG design, named relative to its folder.
public struct SVGFiles: Codable, Equatable, Sendable {
    public var idle: String
    /// Shown while a button is held; falls back to `idle`.
    public var pressed: String?

    public init(idle: String, pressed: String? = nil) {
        self.idle = idle
        self.pressed = pressed
    }
}

/// A hand design ("diseño"). Skins are pure data so new designs can be added
/// in code or loaded from disk without touching rendering logic.
///
/// Two kinds of artwork:
/// - **svg** (preferred): when `svg` is set, the design is a folder with a
///   `skin.json` manifest and SVG files. `hotspot` and `armAnchor` are in the
///   SVG's user units (the root `viewBox`). The SVG bytes are loaded by
///   `SkinRegistry` into `svgData`; they are not part of the manifest.
/// - **pixel** (legacy): `frames` are ASCII pixel art; each character is looked
///   up in `palette`; `.` (or a space) is transparent.
/// See `docs/SKINS.md`.
public struct Skin: Codable, Equatable, Identifiable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public static let transparentSymbols: Set<Character> = [".", " "]

    public var id: String
    public var name: String
    public var author: String?
    /// Pixel designs: single-character symbol -> `#RRGGBB` / `#RRGGBBAA`.
    public var palette: [String: String]
    public var frames: [FrameKind: [String]]
    /// Pixel designs: pixel (frame coordinates, top-left origin) that sits on the real pointer.
    public var hotspot: Point
    /// SVG designs: the files.
    public var svg: SVGFiles?
    /// SVG designs: point (user units) that sits on the real pointer.
    public var svgHotspot: SVGPoint?
    /// SVG designs: where the arm attaches (user units). Defaults to the bottom center.
    public var svgArmAnchor: SVGPoint?
    /// SVG designs: arm width in user units. Defaults to 30% of the viewBox width.
    public var svgArmWidth: Double?
    /// SVG designs: arm and click-burst color (`#RRGGBB`). Defaults to near-black.
    public var arm: String?
    /// SVG designs: the wand behind the hand (`wand` in the manifest). Defaults reproduce the sleeve.
    public var wand = WandConfig()
    /// SVG designs: the click effects (`click` in the manifest).
    public var click = ClickConfig()
    /// SVG designs: file contents by frame, filled in by the loader.
    public var svgData: [FrameKind: Data] = [:]
    /// SVG designs: sleeve and click artwork contents by file name, filled in by the loader.
    public var assetData: [String: Data] = [:]

    /// SVG designs: every extra file the manifest names (sleeve, then click artwork).
    public var assetNames: [String] {
        var names: [String] = []
        for name in (wand.svg?.files ?? []) + (click.svg ?? []) where !names.contains(name) { names.append(name) }
        return names
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, author, palette, frames, hotspot, svg, armAnchor, armWidth, arm, wand, click
    }

    public init(id: String, name: String, author: String? = nil,
                palette: [String: String] = [:], frames: [FrameKind: [String]] = [:],
                hotspot: Point = Point(x: 0, y: 0), svg: SVGFiles? = nil,
                svgHotspot: SVGPoint? = nil, svgArmAnchor: SVGPoint? = nil, svgArmWidth: Double? = nil,
                arm: String? = nil, wand: WandConfig = WandConfig(), click: ClickConfig = ClickConfig(),
                svgData: [FrameKind: Data] = [:]) {
        self.id = id
        self.name = name
        self.author = author
        self.palette = palette
        self.frames = frames
        self.hotspot = hotspot
        self.svg = svg
        self.svgHotspot = svgHotspot
        self.svgArmAnchor = svgArmAnchor
        self.svgArmWidth = svgArmWidth
        self.arm = arm
        self.wand = wand
        self.click = click
        self.svgData = svgData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        frames = try c.decodeIfPresent([FrameKind: [String]].self, forKey: .frames) ?? [:]
        svg = try c.decodeIfPresent(SVGFiles.self, forKey: .svg)
        if svg != nil {
            palette = try c.decodeIfPresent([String: String].self, forKey: .palette) ?? [:]
            hotspot = Point(x: 0, y: 0)
            svgHotspot = try c.decode(SVGPoint.self, forKey: .hotspot)
            svgArmAnchor = try c.decodeIfPresent(SVGPoint.self, forKey: .armAnchor)
            svgArmWidth = try c.decodeIfPresent(Double.self, forKey: .armWidth)
            arm = try c.decodeIfPresent(String.self, forKey: .arm)
            wand = try c.decodeIfPresent(WandConfig.self, forKey: .wand) ?? WandConfig()
            click = try c.decodeIfPresent(ClickConfig.self, forKey: .click) ?? ClickConfig()
        } else {
            // Pixel designs: palette and hotspot stay required, as documented in SKINS.md.
            palette = try c.decode([String: String].self, forKey: .palette)
            hotspot = try c.decode(Point.self, forKey: .hotspot)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(author, forKey: .author)
        if svg != nil {
            try c.encode(svg, forKey: .svg)
            try c.encode(svgHotspot, forKey: .hotspot)
            try c.encodeIfPresent(svgArmAnchor, forKey: .armAnchor)
            try c.encodeIfPresent(svgArmWidth, forKey: .armWidth)
            try c.encodeIfPresent(arm, forKey: .arm)
            if wand != WandConfig() { try c.encode(wand, forKey: .wand) }
            if click != ClickConfig() { try c.encode(click, forKey: .click) }
        } else {
            try c.encode(palette, forKey: .palette)
            try c.encode(frames, forKey: .frames)
            try c.encode(hotspot, forKey: .hotspot)
        }
    }

    /// The root box of the idle SVG, once its data is loaded.
    public var svgViewBox: SVGRect? {
        svgData[.idle].flatMap { try? SVGDocument.parse($0).viewBox }
    }

    /// Throws the first structural problem found.
    public func validate() throws {
        if let svg { return try validateSVG(svg) }
        guard let idle = frames[.idle] else { throw SkinError.missingIdleFrame }
        for (symbol, hex) in palette where symbol.count != 1 || RGBA(hex: hex) == nil {
            throw SkinError.invalidColor("\(symbol): \(hex)")
        }
        for kind in FrameKind.allCases {
            guard let rows = frames[kind] else { continue }
            guard let width = rows.first?.count, width > 0 else { throw SkinError.emptyFrame(frame: kind) }
            guard rows.allSatisfy({ $0.count == width }) else { throw SkinError.raggedRows(frame: kind) }
            for row in rows {
                for symbol in row where !Self.transparentSymbols.contains(symbol) && palette[String(symbol)] == nil {
                    throw SkinError.unknownSymbol(symbol, frame: kind)
                }
            }
        }
        guard hotspot.y >= 0, hotspot.y < idle.count,
              hotspot.x >= 0, hotspot.x < (idle.first?.count ?? 0)
        else { throw SkinError.hotspotOutOfBounds }
    }

    private func validateSVG(_ svg: SVGFiles) throws {
        var files: [(FrameKind, String)] = [(.idle, svg.idle)]
        if let pressed = svg.pressed { files.append((.pressed, pressed)) }
        var boxes: [SVGRect] = []
        for (kind, name) in files {
            guard Self.isPlainSVGName(name) else { throw SkinError.invalidSVGPath(name) }
            guard let data = svgData[kind] else { throw SkinError.missingSVGFile(name) }
            guard let doc = try? SVGDocument.parse(data) else { throw SkinError.invalidSVG(name) }
            boxes.append(doc.viewBox)
        }
        guard boxes.allSatisfy({ $0 == boxes[0] }) else { throw SkinError.viewBoxMismatch }
        let box = boxes[0]
        guard let svgHotspot, box.contains(svgHotspot) else { throw SkinError.hotspotOutOfBounds }
        if let anchor = svgArmAnchor, !box.contains(anchor) { throw SkinError.armAnchorOutOfBounds }
        if let arm, RGBA(hex: arm) == nil { throw SkinError.invalidColor("arm: \(arm)") }
        for name in assetNames {
            guard Self.isPlainSVGName(name) else { throw SkinError.invalidSVGPath(name) }
            guard let data = assetData[name] else { throw SkinError.missingSVGFile(name) }
            guard (try? SVGDocument.parse(data)) != nil else { throw SkinError.invalidSVG(name) }
        }
        try validateStyle()
    }

    /// A file name inside the design folder: no directories, no `..`, ends in `.svg`.
    private static func isPlainSVGName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\")
            && name.lowercased().hasSuffix(".svg")
    }

    /// Renders a pixel frame, falling back to `idle` when the skin doesn't define it.
    public func image(for kind: FrameKind) throws -> PixelImage {
        guard svg == nil else { throw SkinError.notPixelArt }
        try validate()
        let rows = frames[kind] ?? frames[.idle]!
        let colors = palette.compactMapValues(RGBA.init(hex:))
        var pixels: [RGBA?] = []
        for row in rows {
            for symbol in row {
                pixels.append(colors[String(symbol)])
            }
        }
        return PixelImage(width: rows[0].count, height: rows.count, pixels: pixels)
    }
}
