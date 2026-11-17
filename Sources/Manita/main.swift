import AppKit
import ManitaCore

// `Manita --render-preview <out.png> [skin-id-or-json-path] [scale]` writes the
// idle and pressed frames of a design to a PNG and exits. Handy for reviewing designs.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--render-preview") {
    guard arguments.count > flag + 1 else {
        FileHandle.standardError.write(Data("Usage: Manita --render-preview <out.png> [design-id|design.json] [size 1-8]\n".utf8))
        exit(2)
    }
    exit(MainActor.assumeIsolated { PreviewRenderer.run(Array(arguments[(flag + 1)...])) })
}

// `Manita --render-pointer <out.png> [design-id] [scale] [mood 0-3] [light|dark]` writes the whole
// pointer (sleeve, hand, click burst) as it looks on screen for that mood, and exits.
if let flag = arguments.firstIndex(of: "--render-pointer") {
    guard arguments.count > flag + 1 else {
        FileHandle.standardError.write(Data("Usage: Manita --render-pointer <out.png> [design-id] [size 1-8] [mood 0-3] [light|dark]\n".utf8))
        exit(2)
    }
    exit(MainActor.assumeIsolated { PreviewRenderer.runPointer(Array(arguments[(flag + 1)...])) })
}

// Menu bar–only app (LSUIElement): no Dock icon, no main window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
