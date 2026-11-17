import Foundation

/// Locates the SVG designs bundled with the app (one folder per design).
public enum BuiltInSkins {
    /// Folders to pass to `SkinRegistry.register(manifestAt:)`, in menu order.
    public static var folders: [URL] {
        let root = resourceBundle.resourceURL ?? resourceBundle.bundleURL
        return ["cartoon", "cat-paw", "magic-wand"].map { root.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// SwiftPM's generated `Bundle.module` only searches the `.app` root, which is not where
    /// a signed app bundle keeps resources, and it traps when the bundle is missing. Look in
    /// `Contents/Resources` first (packaged app), then fall back to `Bundle.module` (`swift run`).
    private static let resourceBundle: Bundle = {
        let name = "Manita_ManitaSkins.bundle"
        if let url = Bundle.main.resourceURL?.appending(path: name),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
