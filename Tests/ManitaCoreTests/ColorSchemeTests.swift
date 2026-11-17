import Foundation
import Testing
@testable import ManitaCore

/// `colors` (named schemes) of `skin.json`.
@Suite("Color schemes")
struct ColorSchemeTests {
    static let hand = DesignAssetsTests.hand
    static let tile = DesignAssetsTests.tile
    static let otherHand = AppearanceVariantTests.otherHand
    static let bigHand = AppearanceVariantTests.bigHand

    private func manifest(base: String = "", colors: String) -> String {
        ##"{"id":"d","name":"D","svg":{"idle":"idle.svg"},"hotspot":{"x":40,"y":4}"## + base + ##","colors":"## + colors + "}"
    }

    private func load(_ manifest: String, files: [String: String] = [:]) throws -> Skin {
        let dir = FileManager.default.temporaryDirectory.appending(path: "manita-scheme-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(manifest.utf8).write(to: dir.appending(path: "skin.json"))
        for (name, text) in ["idle.svg": Self.hand].merging(files, uniquingKeysWith: { $1 }) {
            try Data(text.utf8).write(to: dir.appending(path: name))
        }
        var registry = SkinRegistry(skins: [])
        return try registry.register(manifestAt: dir)
    }

    private static let two = ##"[{"name":"Ink","wand":{"color":"#111111"},"click":{"color":"#B8322A"}},{"name":"Mint","wand":{"color":"#22AA66"},"click":{"color":"#00FF00"}}]"##

    @Test func schemesAreListedInOrderAndResolveEachOwnColors() throws {
        let skin = try load(manifest(colors: Self.two))
        #expect(skin.schemeNames == ["Ink", "Mint"])
        #expect(skin.resolved(for: .light, scheme: "Ink").wand.color == "#111111")
        #expect(skin.resolved(for: .light, scheme: "Mint").wand.color == "#22AA66")
        #expect(skin.resolved(for: .dark, scheme: "Mint").click.color == "#00FF00")
        #expect(skin.resolved(for: .light, scheme: "Mint").click.color == "#00FF00")
    }

    @Test func unknownOrNilSchemeIsTheFirst() throws {
        let skin = try load(manifest(colors: Self.two))
        #expect(skin.resolved(for: .light, scheme: nil).wand.color == "#111111")
        #expect(skin.resolved(for: .light, scheme: "Nope").wand.color == "#111111")
        #expect(skin.resolved(for: .light).wand.color == "#111111")
    }

    @Test func schemeAppearanceBlocksWinOverDesignBlocks() throws {
        let skin = try load(manifest(
            base: ##","wand":{"color":"#000001"},"dark":{"wand":{"color":"#DDDDDD"}},"light":{"wand":{"color":"#EEEEEE"}}"##,
            colors: ##"[{"name":"A","wand":{"color":"#AAAAAA"},"dark":{"wand":{"color":"#A0A0A0"}}},{"name":"B","wand":{"color":"#BBBBBB"}}]"##))
        #expect(skin.resolved(for: .dark, scheme: "A").wand.color == "#A0A0A0")
        // A has no light block: the design's light block applies after the scheme's own colors.
        #expect(skin.resolved(for: .light, scheme: "A").wand.color == "#EEEEEE")
        // B has no dark block: falls back to the design dark block.
        #expect(skin.resolved(for: .dark, scheme: "B").wand.color == "#DDDDDD")
    }

    @Test func schemeOverridesTheDesignBase() throws {
        let skin = try load(manifest(base: ##","wand":{"color":"#000001","width":30}"##, colors: Self.two))
        #expect(skin.resolved(for: .light, scheme: "Mint").wand.color == "#22AA66")
        #expect(skin.resolved(for: .light, scheme: "Mint").wand.width == 30)
        #expect(skin.resolved(for: .light, scheme: "Mint").schemeNames.isEmpty)
    }

    @Test func schemeFilesLoadAndAreUsed() throws {
        let skin = try load(manifest(colors: ##"[{"name":"A"},{"name":"B","svg":{"idle":"b.svg"},"wand":{"svg":{"tile":"sb.svg"}},"click":{"svg":["cb.svg"]},"dark":{"click":{"svg":["cbd.svg"]}}}]"##),
                            files: ["b.svg": Self.otherHand, "sb.svg": Self.tile, "cb.svg": Self.tile, "cbd.svg": Self.tile])
        let b = skin.resolved(for: .light, scheme: "B")
        #expect(b.svg?.idle == "b.svg")
        #expect(b.svgData[.idle] == Data(Self.otherHand.utf8))
        #expect(b.wand.svg?.tile == "sb.svg")
        #expect(b.click.svg == ["cb.svg"])
        #expect(b.assetData["cb.svg"] != nil)
        #expect(skin.resolved(for: .dark, scheme: "B").click.svg == ["cbd.svg"])
        #expect(skin.resolved(for: .dark, scheme: "B").assetData["cbd.svg"] != nil)
        #expect(skin.resolved(for: .light, scheme: "A").svg?.idle == "idle.svg")
    }

    @Test func schemeWithMissingFileBadPathOrViewBoxIsRejected() {
        #expect(throws: SkinError.missingSVGFile("gone.svg")) {
            try load(manifest(colors: ##"[{"name":"A","wand":{"svg":{"tile":"gone.svg"}}}]"##))
        }
        #expect(throws: SkinError.invalidSVGPath("../x.svg")) {
            try load(manifest(colors: ##"[{"name":"A"},{"name":"B","click":{"svg":["../x.svg"]}}]"##))
        }
        #expect(throws: SkinError.viewBoxMismatch) {
            try load(manifest(colors: ##"[{"name":"A","svg":{"idle":"big.svg"}}]"##), files: ["big.svg": Self.bigHand])
        }
        #expect(throws: SkinError.invalidSVG("bad.svg")) {
            try load(manifest(colors: ##"[{"name":"A","dark":{"wand":{"svg":{"tile":"bad.svg"}}}}]"##), files: ["bad.svg": "<html/>"])
        }
    }

    @Test func schemeWithBadColorIsRejected() {
        #expect(throws: SkinError.invalidColor("wand.color: red")) {
            try load(manifest(colors: ##"[{"name":"A","wand":{"color":"red"}}]"##))
        }
        #expect(throws: SkinError.invalidColor("click.color: nope")) {
            try load(manifest(colors: ##"[{"name":"A"},{"name":"B","light":{"click":{"color":"nope"}}}]"##))
        }
    }

    @Test func duplicateOrEmptySchemeNamesAreRejected() {
        #expect(throws: SkinError.invalidScheme("A")) {
            try load(manifest(colors: ##"[{"name":"A"},{"name":"A"}]"##))
        }
        #expect(throws: SkinError.invalidScheme("")) {
            try load(manifest(colors: ##"[{"name":""}]"##))
        }
    }

    @Test func designWithoutColorsResolvesAsBefore() throws {
        let skin = try load(##"{"id":"d","name":"D","svg":{"idle":"idle.svg"},"hotspot":{"x":40,"y":4},"wand":{"color":"#111111"},"dark":{"wand":{"color":"#F2F2F2D9"}}}"##)
        #expect(skin.schemeNames.isEmpty)
        #expect(skin.resolved(for: .dark, scheme: "Any") == skin.resolved(for: .dark))
        #expect(skin.resolved(for: .dark).wand.color == "#F2F2F2D9")
        #expect(skin.resolved(for: .light).wand.color == "#111111")
    }

    @Test func schemesRoundTripThroughEncoding() throws {
        let skin = try load(manifest(colors: Self.two))
        let again = try JSONDecoder().decode(Skin.self, from: JSONEncoder().encode(skin))
        #expect(again.schemeNames == ["Ink", "Mint"])
        #expect(again.colors == skin.colors)
    }

    @Test func colorSchemesRoundTripThroughTheStore() throws {
        let suite = "manita-scheme-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        var prefs = Preferences.default
        #expect(prefs.colorSchemes.isEmpty)
        prefs.colorSchemes = ["d": "Mint"]
        store.save(prefs)
        #expect(store.load().colorSchemes == ["d": "Mint"])
    }

    @Test func oldStoredPreferencesWithoutSchemesLoad() throws {
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(##"{"mood":3,"skinID":"classic"}"##.utf8))
        #expect(prefs.colorSchemes.isEmpty)
        #expect(prefs.mood == 3)
    }

    @Test func bundledGloveHasDarkAndLightSchemesRegardlessOfAppearance() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Resources/Skins/cartoon").standardized
        var registry = SkinRegistry(skins: [])
        let glove = try registry.register(manifestAt: folder)
        #expect(glove.schemeNames == ["Dark", "Light"])
        for appearance in Appearance.allCases {
            #expect(glove.resolved(for: appearance, scheme: nil).wand.color == "#111111")
            #expect(glove.resolved(for: appearance, scheme: "Nope").wand.color == "#111111")
            #expect(glove.resolved(for: appearance, scheme: "Dark").wand.color == "#111111")
            #expect(glove.resolved(for: appearance, scheme: "Light").wand.color == "#F2F2F2D9")
            #expect(glove.resolved(for: appearance, scheme: "Light").click.color == "#B8322A")
        }
    }
}
