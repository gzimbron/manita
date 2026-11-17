import Foundation

/// Pure description of the "replace system cursors with a transparent one" mechanism.
/// The private-API calls live in the app target; this is the testable data and policy.
/// See docs/adr/0005-replace-system-cursors.md.
public enum CursorOverride {
    /// Names registered by Mousecape's `defaultCursors` and `cursorMap()` (MCDefs.m).
    public static let coreGraphicsNames: [String] = [
        "com.apple.coregraphics.Arrow",
        "com.apple.coregraphics.IBeam",
        "com.apple.coregraphics.IBeamXOR",
        "com.apple.coregraphics.Alias",
        "com.apple.coregraphics.Copy",
        "com.apple.coregraphics.Move",
        "com.apple.coregraphics.ArrowCtx",
        "com.apple.coregraphics.Wait",
        "com.apple.coregraphics.Empty",
    ]

    /// `com.apple.cursor.2 … 43` (link/pointing hand, resize, crosshair, help, zoom…).
    public static let numberedRange: ClosedRange<Int> = 2...43

    /// Every cursor name to override, in a stable order, without duplicates.
    public static var allNames: [String] {
        coreGraphicsNames + numberedRange.map { "com.apple.cursor.\($0)" }
    }

    /// How the real pointer ended up being suppressed.
    public enum Mode: String, Sendable, Equatable {
        case transparentCursor   // preferred: cursors replaced by a transparent image
        case hideCursor          // fallback: CGDisplayHideCursor + SetsCursorInBackground
        case visible             // last resort: pointer left visible under the hand
    }

    /// How a name is put back when Manita stops.
    public enum RestoreStrategy: Sendable, Equatable {
        case systemReset          // `CoreCursorUnregisterAll` + `CoreCursorSet` (numbered cursors)
        case reRegisterOriginal   // re-register the images saved before overriding
        case notOverridden        // Manita never touches this name
    }

    public struct Plan: Sendable, Equatable {
        public let name: String
        public let override: Bool
        public let restore: RestoreStrategy
    }

    /// Only names Manita can restore exactly are overridden. `com.apple.coregraphics.*` names
    /// cannot be unregistered (the remove call fails with 1000), so they are overridden only when
    /// their original images were saved first; numbered names are reset by the system call.
    public static func plan(for name: String, originalSaved: Bool) -> Plan {
        if coreGraphicsNames.contains(name) {
            return originalSaved
                ? Plan(name: name, override: true, restore: .reRegisterOriginal)
                : Plan(name: name, override: false, restore: .notOverridden)
        }
        let prefix = "com.apple.cursor."
        if name.hasPrefix(prefix), let n = Int(name.dropFirst(prefix.count)), numberedRange.contains(n) {
            return Plan(name: name, override: true, restore: .systemReset)
        }
        return Plan(name: name, override: false, restore: .notOverridden)
    }

    /// An override took effect only if reading the image back shows no visible pixel.
    /// (Error code 0 from the register call is not proof: Arrow/IBeam accept it and stay opaque.)
    public static func overrideTook(opaquePixels: Int) -> Bool { opaquePixels == 0 }

    /// A fully transparent 16 pt image under a coregraphics name is what an earlier Manita run leaves behind.
    public static func looksLikeLeftover(pointSize: Int, opaquePixels: Int) -> Bool {
        pointSize == TransparentCursorSpec.standard.pointSize && opaquePixels == 0
    }

    /// Fallback chain: replace → hide → show.
    public static func chooseMode(replaceAvailable: Bool, hideAvailable: Bool) -> Mode {
        if replaceAvailable { return .transparentCursor }
        if hideAvailable { return .hideCursor }
        return .visible
    }
}

/// A fully transparent cursor image: BGRA/RGBA bytes all zero.
public struct TransparentCursorSpec: Equatable, Sendable {
    public let pointSize: Int
    public let scale: Int
    public let hotSpot: (x: Double, y: Double)
    public let frameCount: Int
    public let frameDuration: Double

    public static let standard = TransparentCursorSpec(pointSize: 16, scale: 2)

    public init(pointSize: Int, scale: Int) {
        self.pointSize = max(1, pointSize)
        self.scale = max(1, scale)
        self.hotSpot = (0, 0)
        self.frameCount = 1
        self.frameDuration = 0
    }

    public var pixelSize: Int { pointSize * scale }
    public var bytesPerRow: Int { pixelSize * 4 }
    /// 8-bit RGBA, premultiplied; every byte 0 means fully transparent.
    public var pixels: [UInt8] { [UInt8](repeating: 0, count: bytesPerRow * pixelSize) }

    public static func == (a: Self, b: Self) -> Bool {
        a.pointSize == b.pointSize && a.scale == b.scale
    }
}
