import Foundation
import Testing
@testable import ManitaCore

/// `light` / `dark` blocks of `skin.json`.
@Suite("Light and dark variants")
struct AppearanceVariantTests {
    static let hand = DesignAssetsTests.hand
    static let tile = DesignAssetsTests.tile
    static let otherHand = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 80"><rect width="5" height="5"/></svg>"##
    static let bigHand = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 50"><rect width="5" height="5"/></svg>"##

    private func manifest(base: String = "", extra: String) -> String {
        ##"{"id":"d","name":"D","svg":{"idle":"idle.svg"},"hotspot":{"x":40,"y":4}"## + base + "," + extra + "}"
    }

    private func load(_ manifest: String, files: [String: String] = [:]) throws -> Skin {
        let dir = FileManager.default.temporaryDirectory.appending(path: "manita-variant-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(manifest.utf8).write(to: dir.appending(path: "skin.json"))
        for (name, text) in ["idle.svg": Self.hand].merging(files, uniquingKeysWith: { $1 }) {
            try Data(text.utf8).write(to: dir.appending(path: name))
        }
        var registry = SkinRegistry(skins: [])
        return try registry.register(manifestAt: dir)
    }

    @Test func darkBlockOverridesWandColorAndLightUsesBase() throws {
        let skin = try load(manifest(base: ##","wand":{"color":"#111111","width":30}"##,
                                     extra: ##""dark":{"wand":{"color":"#F2F2F2D9"}}"##))
        #expect(skin.resolved(for: .dark).wand.color == "#F2F2F2D9")
        #expect(skin.resolved(for: .dark).wand.width == 30)
        #expect(skin.resolved(for: .light).wand.color == "#111111")
    }

    @Test func variantClickColorOverridesAndKeepsTheRest() throws {
        let skin = try load(manifest(base: ##","click":{"color":"#B8322A","weight":2}"##,
                                     extra: ##""light":{"click":{"color":"#00FF00"}}"##))
        #expect(skin.resolved(for: .light).click.color == "#00FF00")
        #expect(skin.resolved(for: .light).click.weight == 2)
        #expect(skin.resolved(for: .dark).click.color == "#B8322A")
    }

    @Test func designWithoutBlocksResolvesTheSameForBoth() throws {
        let skin = try load(manifest(base: ##","wand":{"color":"#111111"}"##, extra: ##""arm":"#222222""##))
        #expect(skin.resolved(for: .light) == skin.resolved(for: .dark))
        #expect(skin.resolved(for: .light).wand.color == "#111111")
    }

    @Test func variantFilesLoadAndAreUsed() throws {
        let skin = try load(manifest(base: ##","wand":{"svg":{"tile":"sleeve.svg"}},"click":{"svg":["a.svg"]}"##,
                                     extra: ##""dark":{"svg":{"idle":"idle-dark.svg"},"wand":{"svg":{"tile":"sleeve-dark.svg"}},"click":{"svg":["a-dark.svg"]}}"##),
                            files: ["sleeve.svg": Self.tile, "a.svg": Self.tile, "idle-dark.svg": Self.otherHand,
                                    "sleeve-dark.svg": Self.tile, "a-dark.svg": Self.tile])
        let dark = skin.resolved(for: .dark)
        #expect(dark.svg?.idle == "idle-dark.svg")
        #expect(dark.svgData[.idle] == Data(Self.otherHand.utf8))
        #expect(dark.wand.svg?.tile == "sleeve-dark.svg")
        #expect(dark.assetData["sleeve-dark.svg"] != nil)
        #expect(dark.click.svg == ["a-dark.svg"])
        #expect(dark.assetData["a-dark.svg"] != nil)
        let light = skin.resolved(for: .light)
        #expect(light.svg?.idle == "idle.svg")
        #expect(light.svgData[.idle] == Data(Self.hand.utf8))
        #expect(light.wand.svg?.tile == "sleeve.svg")
    }

    @Test func variantWithMissingFileIsRejected() {
        #expect(throws: SkinError.missingSVGFile("gone.svg")) {
            try load(manifest(extra: ##""dark":{"wand":{"svg":{"tile":"gone.svg"}}}"##))
        }
        #expect(throws: SkinError.missingSVGFile("gone.svg")) {
            try load(manifest(extra: ##""light":{"svg":{"idle":"gone.svg"}}"##))
        }
    }

    @Test func variantWithBadPathIsRejected() {
        #expect(throws: SkinError.invalidSVGPath("../x.svg")) {
            try load(manifest(extra: ##""dark":{"click":{"svg":["../x.svg"]}}"##))
        }
        #expect(throws: SkinError.invalidSVGPath("../x.svg")) {
            try load(manifest(extra: ##""dark":{"svg":{"idle":"../x.svg"}}"##))
        }
    }

    @Test func variantThatIsNotSVGIsRejected() {
        #expect(throws: SkinError.invalidSVG("bad.svg")) {
            try load(manifest(extra: ##""dark":{"wand":{"svg":{"tile":"bad.svg"}}}"##), files: ["bad.svg": "<html/>"])
        }
    }

    @Test func variantHandWithAnotherViewBoxIsRejected() {
        #expect(throws: SkinError.viewBoxMismatch) {
            try load(manifest(extra: ##""dark":{"svg":{"idle":"big.svg"}}"##), files: ["big.svg": Self.bigHand])
        }
    }

    @Test func variantWithBadColorOrRangeIsRejected() {
        #expect(throws: SkinError.invalidColor("wand.color: red")) {
            try load(manifest(extra: ##""dark":{"wand":{"color":"red"}}"##))
        }
        #expect(throws: SkinError.invalidColor("click.color: nope")) {
            try load(manifest(extra: ##""light":{"click":{"color":"nope"}}"##))
        }
        #expect(throws: SkinError.self) {
            try load(manifest(extra: ##""dark":{"click":{"size":50}}"##))
        }
    }

    @Test func variantsRoundTripThroughEncoding() throws {
        let skin = try load(manifest(base: ##","wand":{"color":"#111111"}"##,
                                     extra: ##""dark":{"wand":{"color":"#F2F2F2D9"}},"light":{"click":{"color":"#00FF00"}}"##))
        let again = try JSONDecoder().decode(Skin.self, from: JSONEncoder().encode(skin))
        #expect(again.dark == skin.dark)
        #expect(again.light == skin.light)
        #expect(again.resolved(for: .dark).wand.color == "#F2F2F2D9")
    }

    @Test func savedPointerColorIsIgnored() throws {
        let json = ##"{"pointerColor":"white","mood":3,"scale":7,"skinID":"classic"}"##
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(prefs.mood == 3)
        #expect(prefs.scale == 7)
        #expect(prefs.skinID == "classic")
    }
}
