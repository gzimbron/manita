import Foundation

/// Locates the SVG designs bundled with the app (one folder per design).
public enum BuiltInSkins {
    /// Folders to pass to `SkinRegistry.register(manifestAt:)`, in menu order.
    public static var folders: [URL] {
        ["cartoon", "magic-wand"].map { Bundle.module.resourceURL!.appending(path: $0, directoryHint: .isDirectory) }
    }
}
