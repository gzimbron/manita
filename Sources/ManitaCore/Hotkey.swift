import Foundation

/// A global keyboard shortcut: one key plus modifiers.
///
/// `keyCode` is the hardware virtual key code (layout independent, what the
/// system matches on); `key` is the label shown to the user.
public struct Hotkey: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: Int
    public var key: String
    public var modifiers: Modifiers

    public init(keyCode: Int, key: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    /// ⌃⌥P — show or hide the pointer.
    public static let togglePointer = Hotkey(keyCode: 35, key: "P", modifiers: [.control, .option])
    /// ⌃⌥T — enter or leave presentation mode.
    public static let presentationMode = Hotkey(keyCode: 17, key: "T", modifiers: [.control, .option])

    /// Modifier glyphs in the order macOS draws them, without the key.
    public var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers.contains(.control) { symbols.append("⌃") }
        if modifiers.contains(.option) { symbols.append("⌥") }
        if modifiers.contains(.shift) { symbols.append("⇧") }
        if modifiers.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    /// For menus and messages, e.g. `⌃⌥P`.
    public var display: String {
        modifierSymbols.joined() + key.uppercased()
    }

    /// True when both would fire on the same key press. The label is ignored: one physical
    /// key reads differently across keyboard layouts.
    public func conflicts(with other: Hotkey) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    /// A global shortcut needs a key and ⌃, ⌥ or ⌘; Shift alone would hijack typing.
    public var isValid: Bool {
        !key.isEmpty && keyCode >= 0 && !modifiers.isDisjoint(with: [.control, .option, .command])
    }
}
