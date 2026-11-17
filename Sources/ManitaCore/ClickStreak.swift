import Foundation

/// Counts rapid consecutive presses. Like the reference app, a single or double
/// click only shows the pressed frame and plays the sound; the jab and the burst
/// start from the third press of a streak and grow a little with each further one.
///
/// Pure: feed it monotonic timestamps (for example `ProcessInfo.systemUptime`).
public struct ClickStreak: Equatable, Sendable {
    /// Longest gap between two presses that still belongs to the same streak.
    public static let window: TimeInterval = 0.45
    /// First press of a streak that plays effects.
    public static let effectThreshold = 3
    /// Strength of the press that starts the effects (the mood's own strength).
    public static let baseIntensity = 1.0
    /// Extra strength per press beyond the threshold.
    public static let intensityStep = 0.12
    /// Cap on the strength, however long the streak.
    public static let maxIntensity = 1.4

    /// Presses in the current streak (`0` before any press).
    public private(set) var count = 0
    private var lastPress: TimeInterval?

    public init() {}

    /// Registers a press and returns the new streak length.
    /// A press later than `window` after the previous one, or earlier than it (clock
    /// went backwards), starts a new streak.
    @discardableResult
    public mutating func press(at time: TimeInterval) -> Int {
        if let last = lastPress, time >= last, time - last <= Self.window {
            count += 1
        } else {
            count = 1
        }
        lastPress = time
        return count
    }

    /// Whether the current press should jab and burst.
    public var playsEffects: Bool { count >= Self.effectThreshold }

    /// True when the current press is at least the `threshold`-th of the streak.
    public func playsEffects(from threshold: Int) -> Bool { count >= max(1, threshold) }

    /// How hard the effects land: `0` below the threshold, then `1` growing to `maxIntensity`.
    public var intensity: Double {
        guard playsEffects else { return 0 }
        return min(Self.maxIntensity, Self.baseIntensity + Double(count - Self.effectThreshold) * Self.intensityStep)
    }
}
