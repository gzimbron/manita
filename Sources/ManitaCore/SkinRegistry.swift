import Foundation

/// Catalog of available skins: the code-defined pixel built-ins plus any
/// registered at runtime (the bundled SVG designs and the user's skins folder).
public struct SkinRegistry: Sendable {
    /// Pixel designs defined in code. SVG designs (like Cartoon) live in `Resources/Skins`.
    public static let builtIns: [Skin] = [.classic, .pocket]

    public private(set) var skins: [Skin]

    public init(skins: [Skin] = SkinRegistry.builtIns) {
        self.skins = skins
    }

    /// The skin with `id`, or `.classic` when it is unknown.
    public func skin(id: String) -> Skin {
        skins.first { $0.id == id } ?? .classic
    }

    /// The skin with `id`, or the first registered one (the app's default design) when it is unknown,
    /// for example a design that was removed. `.classic` only when nothing is registered.
    public func skinOrFirst(id: String) -> Skin {
        skins.first { $0.id == id } ?? skins.first ?? .classic
    }

    /// Validates and adds (or replaces) a skin.
    public mutating func register(_ skin: Skin) throws {
        try skin.validate()
        skins.removeAll { $0.id == skin.id }
        skins.append(skin)
    }

    /// Decodes, validates and adds a skin from JSON.
    @discardableResult
    public mutating func register(json: Data) throws -> Skin {
        let skin = try JSONDecoder().decode(Skin.self, from: json)
        try register(skin)
        return skin
    }

    /// Loads a design from a folder (`skin.json` + SVGs) or from a manifest file,
    /// reading SVG files next to it, then validates and registers it.
    @discardableResult
    public mutating func register(manifestAt url: URL) throws -> Skin {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let manifest = isDirectory.boolValue ? url.appending(path: "skin.json") : url
        var skin = try JSONDecoder().decode(Skin.self, from: Data(contentsOf: manifest))
        if let files = skin.svg {
            let folder = manifest.deletingLastPathComponent()
            // Names that could leave the folder are rejected by validate(); don't read them.
            for (kind, name) in [(FrameKind.idle, files.idle as String?), (.pressed, files.pressed)] {
                guard let name, !name.contains("/"), !name.hasPrefix(".") else { continue }
                skin.svgData[kind] = try? Data(contentsOf: folder.appending(path: name))
            }
            for name in skin.assetNames where !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".") {
                skin.assetData[name] = try? Data(contentsOf: folder.appending(path: name))
            }
        }
        try register(skin)
        return skin
    }

    /// Loads every design in `directory`: `*.json` files (pixel) and sub-folders
    /// with a `skin.json` (SVG or pixel). Invalid ones are reported, not fatal.
    public mutating func loadSkins(in directory: URL) -> [(URL, Error)] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var failures: [(URL, Error)] = []
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            let isFolder = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isFolder || entry.pathExtension.lowercased() == "json" else { continue }
            if isFolder, !FileManager.default.fileExists(atPath: entry.appending(path: "skin.json").path) { continue }
            do {
                try register(manifestAt: entry)
            } catch {
                failures.append((entry, error))
            }
        }
        return failures
    }
}

// MARK: - Built-in skins

extension Skin {
    /// Descriptor of the bundled Cartoon design (the default). Its artwork is
    /// the SVG folder `Resources/Skins/cartoon`, loaded with `register(manifestAt:)`;
    /// this value carries no SVG data and is not validated on its own.
    public static let cartoon = Skin(id: "cartoon", name: "Glove", author: "Manita",
                                     svg: SVGFiles(idle: "idle.svg", pressed: "pressed.svg"))

    /// Original retro pointing hand, idle frame.
    static let handIdle = [
        ".....##.........",
        "....#ww#........",
        "....#ww#........",
        "....#ww#........",
        "....#ww###......",
        "....#ww#ww###...",
        "..###ww#ww#ww##.",
        ".#ww#wwwwwwww#w#",
        ".#wwwwwwwwwwwww#",
        "..#wwwwwwwwwwww#",
        "..#wwwwwwwwwwww#",
        "...#wwwwwwwwww#.",
        "...#wwwwwwwwww#.",
        "....#wwwwwwww#..",
        "....#ssssssss#..",
        "....##########..",
    ]

    /// Pressed frame: the index finger is pushed down two pixels.
    static let handPressed: [String] = {
        let blank = String(repeating: ".", count: handIdle[0].count)
        return [blank, blank, handIdle[0]] + handIdle[3...]
    }()

    public static let classic = Skin(
        id: "classic",
        name: "Classic",
        author: "Manita",
        palette: ["#": "#1A1A2E", "w": "#FFFFFF", "s": "#C9C9D6"],
        frames: [.idle: handIdle, .pressed: handPressed],
        hotspot: Point(x: 5, y: 0)
    )

    /// Same hand in a four-shade green handheld-console palette.
    public static let pocket = Skin(
        id: "pocket",
        name: "Pocket",
        author: "Manita",
        palette: ["#": "#0F380F", "w": "#9BBC0F", "s": "#306230"],
        frames: [.idle: handIdle, .pressed: handPressed],
        hotspot: Point(x: 5, y: 0)
    )
}
