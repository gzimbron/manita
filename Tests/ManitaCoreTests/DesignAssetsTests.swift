import Foundation
import Testing
@testable import ManitaCore

/// Designable sleeve (`wand.svg`) and click burst (`click.svg`) artwork in a design folder.
@Suite("Design assets")
struct DesignAssetsTests {
    static let hand = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 80"><path d="M0 0h10v10z"/></svg>"#
    static let tile = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 20"><rect width="30" height="20"/></svg>"#

    private func manifest(wand: String? = nil, click: String? = nil) -> String {
        var text = #"{"id":"d","name":"D","svg":{"idle":"idle.svg"},"hotspot":{"x":40,"y":4}"#
        if let wand { text += #","wand":"# + wand }
        if let click { text += #","click":"# + click }
        return text + "}"
    }

    private func load(_ manifest: String, files: [String: String]) throws -> Skin {
        let dir = FileManager.default.temporaryDirectory.appending(path: "manita-assets-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(manifest.utf8).write(to: dir.appending(path: "skin.json"))
        for (name, text) in ["idle.svg": Self.hand].merging(files, uniquingKeysWith: { $1 }) {
            try Data(text.utf8).write(to: dir.appending(path: name))
        }
        var registry = SkinRegistry(skins: [])
        return try registry.register(manifestAt: dir)
    }

    // MARK: - Sleeve

    @Test func sleeveArtLoadsTileAndCuff() throws {
        let skin = try load(manifest(wand: #"{"svg":{"tile":"sleeve.svg","cuff":"cuff.svg"},"tint":true}"#),
                            files: ["sleeve.svg": Self.tile, "cuff.svg": Self.tile])
        #expect(skin.wand.svg == WandArt(tile: "sleeve.svg", cuff: "cuff.svg"))
        #expect(skin.wand.tint)
        #expect(skin.assetData["sleeve.svg"] != nil && skin.assetData["cuff.svg"] != nil)
    }

    @Test func sleeveCuffIsOptional() throws {
        let skin = try load(manifest(wand: #"{"svg":{"tile":"sleeve.svg"}}"#), files: ["sleeve.svg": Self.tile])
        #expect(skin.wand.svg == WandArt(tile: "sleeve.svg"))
        #expect(!skin.wand.tint)
    }

    @Test func sleeveWithMissingFileIsRejected() {
        #expect(throws: SkinError.missingSVGFile("sleeve.svg")) {
            try load(manifest(wand: #"{"svg":{"tile":"sleeve.svg"}}"#), files: [:])
        }
    }

    @Test func sleeveOutsideTheFolderIsRejected() {
        #expect(throws: SkinError.invalidSVGPath("../sleeve.svg")) {
            try load(manifest(wand: #"{"svg":{"tile":"../sleeve.svg"}}"#), files: [:])
        }
    }

    @Test func sleeveThatIsNotSVGIsRejected() {
        #expect(throws: SkinError.invalidSVG("sleeve.svg")) {
            try load(manifest(wand: #"{"svg":{"tile":"sleeve.svg"}}"#), files: ["sleeve.svg": "<html/>"])
        }
    }

    @Test func designWithoutSleeveArtKeepsThePreset() throws {
        let skin = try load(manifest(wand: #"{"style":"stick","width":7}"#), files: [:])
        #expect(skin.wand.svg == nil)
        #expect(skin.wand.style == .stick && skin.wand.width == 7 && !skin.wand.tint)
        #expect(skin.assetData.isEmpty)
    }

    @Test func bundledGloveShipsItsSleeve() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var registry = SkinRegistry()
        let skin = try registry.register(manifestAt: repo.appending(path: "Resources/Skins/cartoon"))
        let tile = try #require(skin.wand.svg?.tile)
        #expect(skin.assetData[tile] != nil)
    }
}
