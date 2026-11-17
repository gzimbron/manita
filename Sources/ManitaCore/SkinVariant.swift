import Foundation

/// The system appearance a design is drawn for.
public enum Appearance: String, Codable, CaseIterable, Sendable {
    case light
    case dark
}

/// What a `light` or `dark` block of `skin.json` may change: the hand files and the wand and click fields.
/// Anything left out comes from the design's base.
public struct SkinVariant: Codable, Equatable, Sendable {
    public struct Hand: Codable, Equatable, Sendable {
        public var idle: String?
        public var pressed: String?
        public init(idle: String? = nil, pressed: String? = nil) {
            self.idle = idle
            self.pressed = pressed
        }
    }

    public struct Wand: Codable, Equatable, Sendable {
        public var color: String?
        public var width: Double?
        public var style: WandStyle?
        public var fade: Bool?
        public var svg: WandArt?
        public var tint: Bool?
        public init(color: String? = nil, width: Double? = nil, style: WandStyle? = nil, fade: Bool? = nil,
                    svg: WandArt? = nil, tint: Bool? = nil) {
            self.color = color; self.width = width; self.style = style
            self.fade = fade; self.svg = svg; self.tint = tint
        }
    }

    public struct Click: Codable, Equatable, Sendable {
        public var bursts: [BurstKind]?
        public var color: String?
        public var weight: Double?
        public var svg: [String]?
        public var size: Double?
        public var tint: Bool?
        public var animation: BurstAnimation?
        public init(bursts: [BurstKind]? = nil, color: String? = nil, weight: Double? = nil, svg: [String]? = nil,
                    size: Double? = nil, tint: Bool? = nil, animation: BurstAnimation? = nil) {
            self.bursts = bursts; self.color = color; self.weight = weight; self.svg = svg
            self.size = size; self.tint = tint; self.animation = animation
        }
    }

    public var svg: Hand?
    public var wand: Wand?
    public var click: Click?

    public init(svg: Hand? = nil, wand: Wand? = nil, click: Click? = nil) {
        self.svg = svg; self.wand = wand; self.click = click
    }

    /// Every file this block names.
    var fileNames: [String] {
        [svg?.idle, svg?.pressed].compactMap { $0 } + (wand?.svg?.files ?? []) + (click?.svg ?? [])
    }
}

/// A named color scheme of a design (`colors` in `skin.json`): overrides over the design base
/// (same shape as a variant block) plus optional `light` / `dark` blocks of its own.
public struct ColorScheme: Codable, Equatable, Sendable {
    public var name: String
    public var svg: SkinVariant.Hand?
    public var wand: SkinVariant.Wand?
    public var click: SkinVariant.Click?
    public var light: SkinVariant?
    public var dark: SkinVariant?

    public init(name: String, svg: SkinVariant.Hand? = nil, wand: SkinVariant.Wand? = nil,
                click: SkinVariant.Click? = nil, light: SkinVariant? = nil, dark: SkinVariant? = nil) {
        self.name = name; self.svg = svg; self.wand = wand; self.click = click
        self.light = light; self.dark = dark
    }

    /// The scheme's own overrides, without its appearance blocks.
    var base: SkinVariant { SkinVariant(svg: svg, wand: wand, click: click) }

    func variant(for appearance: Appearance) -> SkinVariant? {
        appearance == .light ? light : dark
    }

    /// Every file this scheme names, in any of its blocks.
    var fileNames: [String] {
        base.fileNames + (light?.fileNames ?? []) + (dark?.fileNames ?? [])
    }
}

extension Skin {
    public func variant(for appearance: Appearance) -> SkinVariant? {
        appearance == .light ? light : dark
    }

    /// The names of the design's color schemes, in manifest order. Empty: no schemes.
    public var schemeNames: [String] { (colors ?? []).map(\.name) }

    /// The design as drawn in `appearance` with its first color scheme (the base when it has none).
    public func resolved(for appearance: Appearance) -> Skin {
        resolved(for: appearance, scheme: nil)
    }

    /// The design as drawn in `appearance` with the scheme called `scheme` (`nil` or unknown: the first).
    /// Order: base, then the scheme's overrides, then the scheme's block for the appearance
    /// (the design-level block when the scheme has none). The result carries no blocks or schemes.
    /// Designs without schemes and blocks (and pixel designs) come back unchanged.
    public func resolved(for appearance: Appearance, scheme: String?) -> Skin {
        var skin = self
        skin.light = nil
        skin.dark = nil
        skin.colors = nil
        guard svg != nil else { return skin }
        let chosen = (colors ?? []).first { $0.name == scheme } ?? colors?.first
        if let chosen { skin.apply(chosen.base, from: self) }
        if let block = chosen?.variant(for: appearance) ?? variant(for: appearance) { skin.apply(block, from: self) }
        return skin
    }

    private mutating func apply(_ v: SkinVariant, from source: Skin) {
        if let hand = v.svg {
            if let idle = hand.idle {
                svg?.idle = idle
                svgData[.idle] = source.assetData[idle]
            }
            if let pressed = hand.pressed {
                svg?.pressed = pressed
                svgData[.pressed] = source.assetData[pressed]
            }
        }
        if let w = v.wand {
            if let x = w.color { wand.color = x }
            if let x = w.width { wand.width = x }
            if let x = w.style { wand.style = x }
            if let x = w.fade { wand.fade = x }
            if let x = w.svg { wand.svg = x }
            if let x = w.tint { wand.tint = x }
        }
        if let c = v.click {
            if let x = c.bursts { click.bursts = x.isEmpty ? nil : x }
            if let x = c.color { click.color = x }
            if let x = c.weight { click.weight = x }
            if let x = c.svg { click.svg = x.isEmpty ? nil : x }
            if let x = c.size { click.size = x }
            if let x = c.tint { click.tint = x }
            if let x = c.animation { click.animation = x }
        }
    }

    /// Rejects empty and duplicate scheme names.
    func validateSchemes() throws {
        var seen: Set<String> = []
        for scheme in colors ?? [] {
            guard !scheme.name.isEmpty, seen.insert(scheme.name).inserted else {
                throw SkinError.invalidScheme(scheme.name)
            }
        }
    }

    /// Validates each appearance's effective design: its hand files share the base viewBox,
    /// its other files exist and are SVG, and its colors and ranges are valid.
    func validateVariants(box: SVGRect) throws {
        // Every scheme (or the base alone) in each appearance that changes anything.
        var combos: [(Appearance, String?)] = []
        for appearance in Appearance.allCases {
            if colors?.isEmpty ?? true {
                if variant(for: appearance) != nil { combos.append((appearance, nil)) }
            } else {
                combos += schemeNames.map { (appearance, $0) }
            }
        }
        for (appearance, scheme) in combos {
            let r = resolved(for: appearance, scheme: scheme)
            guard let files = r.svg else { continue }
            var hands: [(FrameKind, String)] = [(.idle, files.idle)]
            if let pressed = files.pressed { hands.append((.pressed, pressed)) }
            for (kind, name) in hands {
                guard Self.isPlainSVGName(name) else { throw SkinError.invalidSVGPath(name) }
                guard let data = r.svgData[kind] else { throw SkinError.missingSVGFile(name) }
                guard let doc = try? SVGDocument.parse(data) else { throw SkinError.invalidSVG(name) }
                guard doc.viewBox == box else { throw SkinError.viewBoxMismatch }
            }
            for name in r.assetNames {
                guard Self.isPlainSVGName(name) else { throw SkinError.invalidSVGPath(name) }
                guard let data = r.assetData[name] else { throw SkinError.missingSVGFile(name) }
                guard (try? SVGDocument.parse(data)) != nil else { throw SkinError.invalidSVG(name) }
            }
            try r.validateStyle()
        }
    }
}
