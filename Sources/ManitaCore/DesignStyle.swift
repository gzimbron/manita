import Foundation

/// How the wand ("varita") behind the hand is drawn.
public enum WandStyle: String, Codable, CaseIterable, Sendable {
    /// A solid bar as wide as the cuff that fades out (the original look).
    case sleeve
    /// A metal telescopic pointer: segments joined by collars, thinner away from the hand.
    case stick
}

/// A sleeve drawn by the design: `wand.svg` in `skin.json`. File names are relative to the design folder.
public struct WandArt: Codable, Equatable, Sendable {
    /// Repeated along the sleeve, away from the hand; its viewBox width spans the sleeve's width.
    public var tile: String
    /// Drawn once at the hand end, before the first tile. Optional.
    public var cuff: String?

    public init(tile: String, cuff: String? = nil) {
        self.tile = tile
        self.cuff = cuff
    }

    /// The files this art needs, cuff first.
    public var files: [String] { [cuff, tile].compactMap { $0 } }
}

/// The wand a design draws behind its hand: `wand` in `skin.json`.
/// Missing fields take the defaults that reproduce the original sleeve.
public struct WandConfig: Codable, Equatable, Sendable {
    /// `#RRGGBB` / `#RRGGBBAA`. `nil`: the design's `arm` color, then near-black.
    public var color: String?
    /// Width in the SVG's user units. `nil`: the design's `armWidth`, then 30% of the viewBox width.
    public var width: Double?
    public var style: WandStyle
    /// Whether the wand fades out along its length. `nil`: sleeves fade, sticks do not.
    public var fade: Bool?
    /// The design's own sleeve artwork; replaces `style` when set.
    public var svg: WandArt?
    /// Draw `svg` in the wand color (its shapes become a mask), so the Color setting applies to it.
    public var tint: Bool

    public init(color: String? = nil, width: Double? = nil, style: WandStyle = .sleeve, fade: Bool? = nil,
                svg: WandArt? = nil, tint: Bool = false) {
        self.color = color
        self.width = width
        self.style = style
        self.fade = fade
        self.svg = svg
        self.tint = tint
    }

    public var fades: Bool { fade ?? (style == .sleeve) }

    private enum CodingKeys: String, CodingKey { case color, width, style, fade, svg, tint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        style = try c.decodeIfPresent(WandStyle.self, forKey: .style) ?? .sleeve
        fade = try c.decodeIfPresent(Bool.self, forKey: .fade)
        svg = try c.decodeIfPresent(WandArt.self, forKey: .svg)
        tint = try c.decodeIfPresent(Bool.self, forKey: .tint) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encode(style, forKey: .style)
        try c.encodeIfPresent(fade, forKey: .fade)
        try c.encodeIfPresent(svg, forKey: .svg)
        if tint { try c.encode(tint, forKey: .tint) }
    }
}

/// The shapes a click burst can take.
public enum BurstKind: String, Codable, CaseIterable, Sendable {
    /// The website's burst: 12 rays around a filled 10-point star with an ink outline. The default.
    case classic
    /// Straight rays around the click.
    case rays
    /// A comic "pow" star outline.
    case star
    /// An expanding ring.
    case ring
}

/// The click effects a design draws: `click` in `skin.json`.
public struct ClickConfig: Codable, Equatable, Sendable {
    public static let weightRange = 0.25...4.0

    /// Burst kinds cycled one per effect. `nil`: the classic burst.
    public var bursts: [BurstKind]?
    /// `#RRGGBB` / `#RRGGBBAA`. `nil`: the wand's color.
    public var color: String?
    /// Line width multiplier.
    public var weight: Double

    public init(bursts: [BurstKind]? = nil, color: String? = nil, weight: Double = 1) {
        self.bursts = bursts
        self.color = color
        self.weight = weight
    }

    private enum CodingKeys: String, CodingKey { case bursts, color, weight }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decodeIfPresent([BurstKind].self, forKey: .bursts)
        bursts = list?.isEmpty == true ? nil : list
        color = try c.decodeIfPresent(String.self, forKey: .color)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
    }

    /// The burst for the `effect`-th effect played (1-based).
    /// - Parameter comic: the mood allows comic stars; kept for callers, the default burst is always classic.
    public func burst(forEffect effect: Int, comic: Bool) -> BurstKind {
        if let bursts, !bursts.isEmpty {
            return bursts[(max(effect, 1) - 1) % bursts.count]
        }
        return .classic
    }
}

extension Skin {
    /// Wand thickness in user units: `wand.width`, else `armWidth`.
    public var resolvedArmWidth: Double? { wand.width ?? svgArmWidth }
    /// Wand color: `wand.color`, else `arm`.
    public var resolvedWandColor: String? { wand.color ?? arm }
    /// Click effect color: `click.color`, else the wand's.
    public var resolvedClickColor: String? { click.color ?? resolvedWandColor }

    func validateStyle() throws {
        if let color = wand.color, RGBA(hex: color) == nil { throw SkinError.invalidColor("wand.color: \(color)") }
        if let width = wand.width, !(width.isFinite && width > 0) { throw SkinError.invalidWand("width must be above 0") }
        if let color = click.color, RGBA(hex: color) == nil { throw SkinError.invalidColor("click.color: \(color)") }
        guard click.weight.isFinite, ClickConfig.weightRange.contains(click.weight) else {
            throw SkinError.invalidClick("weight must be from \(ClickConfig.weightRange.lowerBound) to \(ClickConfig.weightRange.upperBound)")
        }
    }
}
