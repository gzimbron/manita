import Foundation

/// How loud the pointer is, from a discreet finger (`0`) to impossible to miss (`3`).
///
/// The mood never changes the hand itself: it drives the sleeve (bolder and
/// longer as it grows) and how hard a click lands (jab, shake trail, burst).
public struct MoodStyle: Equatable, Sendable {
    /// Sleeve width, as a multiple of the design's own arm width.
    public var armWidthScale: Double
    /// Sleeve length, in hand heights.
    public var armLengthInHands: Double
    /// Peak sleeve opacity, `0...1`.
    public var armOpacity: Double
    /// Share of the sleeve that stays at peak opacity before it fades out.
    public var armOpaqueFraction: Double
    /// How far the hand jabs forward on a click, in hand heights.
    public var jabDistance: Double
    /// Number of back-and-forth jabs per click.
    public var jabCount: Int
    /// Sideways shake during the jab, in hand heights.
    public var shakeDistance: Double
    /// Seconds the whole jab takes.
    public var jabDuration: Double
    /// Faded copies trailing the hand while it jabs.
    public var trailCount: Int
    /// Click burst radius, in hand heights.
    public var burstRadius: Double
    /// Rays in the click burst.
    public var burstRays: Int
    /// Burst line width, as a multiple of the base width.
    public var burstWeight: Double
    /// Bursts alternate between rays and comic "pow" shapes.
    public var comicBursts: Bool
    /// Seconds a faint ring stays after the burst (`0`: none). At most `Mood.maxLingerDuration`.
    public var lingerDuration: Double
}

public enum Mood {
    public static let range = 0...3
    public static let `default` = 1
    /// Seconds a click burst takes, start to finish.
    public static let burstDuration = 0.3
    /// Seconds the classic (website) burst takes.
    public static let classicBurstDuration = 0.4
    /// Longest a faint ring may linger after the burst.
    public static let maxLingerDuration = 0.35

    /// The style for `level`; out-of-range levels use the nearest one.
    public static func style(_ level: Int) -> MoodStyle {
        styles[min(max(level, range.lowerBound), range.upperBound)]
    }

    private static let styles: [MoodStyle] = [
        MoodStyle(armWidthScale: 0.7, armLengthInHands: 3, armOpacity: 0.55, armOpaqueFraction: 0.05,
                  jabDistance: 0.08, jabCount: 1, shakeDistance: 0, jabDuration: 0.14, trailCount: 0,
                  burstRadius: 0.6, burstRays: 6, burstWeight: 0.8, comicBursts: false, lingerDuration: 0),
        MoodStyle(armWidthScale: 0.9, armLengthInHands: 6, armOpacity: 0.85, armOpaqueFraction: 0.45,
                  jabDistance: 0.16, jabCount: 1, shakeDistance: 0.03, jabDuration: 0.18, trailCount: 0,
                  burstRadius: 0.8, burstRays: 9, burstWeight: 1, comicBursts: false, lingerDuration: 0.2),
        MoodStyle(armWidthScale: 1.05, armLengthInHands: 10, armOpacity: 1, armOpaqueFraction: 0.7,
                  jabDistance: 0.26, jabCount: 2, shakeDistance: 0.07, jabDuration: 0.24, trailCount: 1,
                  burstRadius: 1.05, burstRays: 12, burstWeight: 1.25, comicBursts: false, lingerDuration: 0.3),
        MoodStyle(armWidthScale: 1.2, armLengthInHands: 16, armOpacity: 1, armOpaqueFraction: 0.85,
                  jabDistance: 0.38, jabCount: 3, shakeDistance: 0.12, jabDuration: 0.3, trailCount: 2,
                  burstRadius: 1.35, burstRays: 16, burstWeight: 1.6, comicBursts: true, lingerDuration: 0.35),
    ]
}

/// Color of the sleeve and click effects.
public enum PointerColor: String, Codable, CaseIterable, Sendable {
    /// Black on a light desktop, white in Dark Mode.
    case automatic
    case black
    case white
    /// Whatever the design declares (`arm` in `skin.json`, or the pixel outline).
    case design

    /// The color to draw, or `nil` to use the design's own.
    public func resolved(systemIsDark: Bool) -> RGBA? {
        switch self {
        case .automatic: systemIsDark ? Self.light : Self.dark
        case .black: Self.dark
        case .white: Self.light
        case .design: nil
        }
    }

    static let dark = RGBA(r: 0x11, g: 0x11, b: 0x11)
    static let light = RGBA(r: 0xF2, g: 0xF2, b: 0xF2, a: 0xD9)
}
