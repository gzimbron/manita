import Foundation

/// User-facing settings. Every effect can be toggled independently.
public struct Preferences: Codable, Equatable, Sendable {
    /// Master switch: when false the overlay is hidden and no effects play.
    public var isEnabled: Bool
    /// Play a retro sound on every click.
    public var soundEnabled: Bool
    /// Animate the hand (press frame + burst lines) on every click.
    public var clickAnimationEnabled: Bool
    /// Sound volume, `0...1`.
    public var volume: Double
    /// Integer pixel scale of the hand (pixel art stays crisp).
    public var scale: Int
    /// Identifier of the active `Skin`.
    public var skinID: String
    /// Hide the real macOS pointer so only the hand is visible.
    public var hideSystemCursor: Bool
    /// Draw a long cartoon arm behind the hand.
    public var showArm: Bool
    /// Pointer mood, `Mood.range`: how bold the sleeve is and how hard clicks land.
    public var mood: Int
    /// Color of the sleeve and click effects (Dark Mode support).
    public var pointerColor: PointerColor
    /// Global shortcut that shows or hides the pointer.
    public var pointerHotkey: Hotkey
    /// Global shortcut that toggles presentation mode.
    public var presentationHotkey: Hotkey

    /// From which rapid click of a streak the bursts and the shake play (the bounce plays on every click).
    public var effectsFromClick: Int
    public static let effectsFromClickRange = 1...10

    public static let scaleRange = 1...8

    public static let `default` = Preferences(
        isEnabled: true,
        soundEnabled: true,
        clickAnimationEnabled: true,
        volume: 0.6,
        scale: 5,
        skinID: Skin.cartoon.id,
        hideSystemCursor: true,
        showArm: true
    )

    public init(isEnabled: Bool, soundEnabled: Bool, clickAnimationEnabled: Bool,
                volume: Double, scale: Int, skinID: String, hideSystemCursor: Bool, showArm: Bool,
                mood: Int = Mood.default, pointerColor: PointerColor = .automatic,
                pointerHotkey: Hotkey = .togglePointer, presentationHotkey: Hotkey = .presentationMode) {
        self.mood = mood
        self.effectsFromClick = 3
        self.pointerColor = pointerColor
        self.pointerHotkey = pointerHotkey
        self.presentationHotkey = presentationHotkey
        self.showArm = showArm
        self.hideSystemCursor = hideSystemCursor
        self.isEnabled = isEnabled
        self.soundEnabled = soundEnabled
        self.clickAnimationEnabled = clickAnimationEnabled
        self.volume = volume
        self.scale = scale
        self.skinID = skinID
    }

    /// Tolerant decoding: any field missing from older saved data takes its default,
    /// so adding a preference never resets the user's existing settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.default
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? d.soundEnabled
        clickAnimationEnabled = try c.decodeIfPresent(Bool.self, forKey: .clickAnimationEnabled) ?? d.clickAnimationEnabled
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? d.volume
        scale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? d.scale
        skinID = try c.decodeIfPresent(String.self, forKey: .skinID) ?? d.skinID
        hideSystemCursor = try c.decodeIfPresent(Bool.self, forKey: .hideSystemCursor) ?? d.hideSystemCursor
        showArm = try c.decodeIfPresent(Bool.self, forKey: .showArm) ?? d.showArm
        effectsFromClick = try c.decodeIfPresent(Int.self, forKey: .effectsFromClick) ?? d.effectsFromClick
        mood = try c.decodeIfPresent(Int.self, forKey: .mood) ?? d.mood
        // A value this version cannot read falls back instead of failing the whole load.
        pointerColor = (try? c.decodeIfPresent(PointerColor.self, forKey: .pointerColor)) ?? d.pointerColor
        pointerHotkey = (try? c.decodeIfPresent(Hotkey.self, forKey: .pointerHotkey)) ?? d.pointerHotkey
        presentationHotkey = (try? c.decodeIfPresent(Hotkey.self, forKey: .presentationHotkey)) ?? d.presentationHotkey
    }

    /// Returns a copy with every numeric value inside its valid range.
    public func clamped() -> Preferences {
        var copy = self
        copy.volume = min(max(volume, 0), 1)
        copy.scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        copy.effectsFromClick = min(max(effectsFromClick, Self.effectsFromClickRange.lowerBound),
                                    Self.effectsFromClickRange.upperBound)
        copy.mood = min(max(mood, Mood.range.lowerBound), Mood.range.upperBound)
        if !pointerHotkey.isValid { copy.pointerHotkey = .togglePointer }
        if !presentationHotkey.isValid { copy.presentationHotkey = .presentationMode }
        // Two actions cannot share a shortcut: the presentation one gives way.
        if copy.presentationHotkey.conflicts(with: copy.pointerHotkey) {
            copy.presentationHotkey = copy.pointerHotkey.conflicts(with: .presentationMode) ? .togglePointer : .presentationMode
        }
        return copy
    }
}

/// Persists `Preferences` as JSON in `UserDefaults`.
public final class PreferencesStore: @unchecked Sendable {
    public static let key = "manita.preferences.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads stored preferences; missing or unreadable data yields `.default`.
    public func load() -> Preferences {
        guard let data = defaults.data(forKey: Self.key),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return .default }
        return prefs.clamped()
    }

    public func save(_ prefs: Preferences) {
        guard let data = try? JSONEncoder().encode(prefs.clamped()) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
