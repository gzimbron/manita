import Foundation
import Testing
@testable import ManitaCore

@Suite("DesignStyle")
struct DesignStyleTests {
    private static let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"></svg>"#.utf8)

    /// A design folder's `skin.json` text with `extra` spliced in after the hotspot.
    private func skin(extra: String = "") throws -> Skin {
        let json = """
        {"id": "t", "name": "T", "svg": {"idle": "idle.svg"}, "hotspot": {"x": 10, "y": 10}\(extra)}
        """
        var skin = try JSONDecoder().decode(Skin.self, from: Data(json.utf8))
        skin.svgData[.idle] = Self.svg
        return skin
    }

    // MARK: Defaults reproduce today's look

    @Test func missingWandAndClickUseTodaysLook() throws {
        let skin = try skin()
        #expect(skin.wand == WandConfig())
        #expect(skin.click == ClickConfig())
        #expect(skin.wand.style == .sleeve)
        #expect(skin.wand.fades)
        #expect(skin.click.weight == 1)
        #expect(skin.click.bursts == nil)
        try skin.validate()
    }

    @Test func legacyArmFieldsStillWork() throws {
        let skin = try skin(extra: ##", "armWidth": 26, "arm": "#112233""##)
        #expect(skin.resolvedArmWidth == 26)
        #expect(skin.resolvedWandColor == "#112233")
        #expect(skin.resolvedClickColor == "#112233")
        try skin.validate()
    }

    @Test func noColorOrWidthAnywhereMeansNil() throws {
        let skin = try skin()
        #expect(skin.resolvedArmWidth == nil)
        #expect(skin.resolvedWandColor == nil)
        #expect(skin.resolvedClickColor == nil)
    }

    // MARK: Wand

    @Test func wandFieldsAreDecodedAndWinOverTheLegacyOnes() throws {
        let skin = try skin(extra: """
        , "armWidth": 26, "arm": "#111111",
        "wand": {"color": "#C8CCD2", "width": 9, "style": "stick", "fade": false}
        """)
        #expect(skin.wand.style == .stick)
        #expect(skin.wand.fades == false)
        #expect(skin.resolvedArmWidth == 9)
        #expect(skin.resolvedWandColor == "#C8CCD2")
        // Effects follow the wand color unless `click.color` says otherwise.
        #expect(skin.resolvedClickColor == "#C8CCD2")
        try skin.validate()
    }

    @Test func aStickDoesNotFadeUnlessAsked() throws {
        #expect(try skin(extra: ##", "wand": {"style": "stick"}"##).wand.fades == false)
        #expect(try skin(extra: ##", "wand": {"style": "stick", "fade": true}"##).wand.fades)
        #expect(try skin(extra: ##", "wand": {"style": "sleeve", "fade": false}"##).wand.fades == false)
        #expect(try skin(extra: ##", "wand": {}"##).wand == WandConfig())
    }

    @Test func wandColorAcceptsAlpha() throws {
        try skin(extra: ##", "wand": {"color": "#11223380"}"##).validate()
    }

    @Test func badWandValuesAreRejected() throws {
        #expect(throws: SkinError.invalidColor("wand.color: red")) {
            try skin(extra: ##", "wand": {"color": "red"}"##).validate()
        }
        #expect(throws: SkinError.self) { try skin(extra: ##", "wand": {"width": 0}"##).validate() }
        #expect(throws: SkinError.self) { try skin(extra: ##", "wand": {"width": -3}"##).validate() }
        #expect(throws: DecodingError.self) { try skin(extra: ##", "wand": {"style": "rope"}"##) }
    }

    // MARK: Click

    @Test func clickFieldsAreDecoded() throws {
        let skin = try skin(extra: ##", "click": {"bursts": ["ring", "star", "rays"], "color": "#FF0000", "weight": 1.5}"##)
        #expect(skin.click.bursts == [.ring, .star, .rays])
        #expect(skin.click.color == "#FF0000")
        #expect(skin.click.weight == 1.5)
        #expect(skin.resolvedClickColor == "#FF0000")
        try skin.validate()
    }

    @Test func badClickValuesAreRejected() throws {
        #expect(throws: SkinError.invalidColor("click.color: nope")) {
            try skin(extra: ##", "click": {"color": "nope"}"##).validate()
        }
        #expect(throws: SkinError.self) { try skin(extra: ##", "click": {"weight": 0}"##).validate() }
        #expect(throws: SkinError.self) { try skin(extra: ##", "click": {"weight": 99}"##).validate() }
        #expect(throws: DecodingError.self) { try skin(extra: ##", "click": {"bursts": ["spark"]}"##) }
    }

    @Test func anEmptyBurstListFallsBackToTheDefaults() throws {
        #expect(try skin(extra: ##", "click": {"bursts": []}"##).click.bursts == nil)
    }

    @Test func burstsCycleInOrderPerEffect() {
        let click = ClickConfig(bursts: [.ring, .star, .rays])
        let kinds = (1...7).map { click.burst(forEffect: $0, comic: false) }
        #expect(kinds == [.ring, .star, .rays, .ring, .star, .rays, .ring])
        // The mood's comic flag only matters for designs that do not list bursts.
        #expect(click.burst(forEffect: 1, comic: true) == .ring)
    }

    @Test func defaultBurstIsTheClassicOne() {
        let click = ClickConfig()
        #expect((1...4).map { click.burst(forEffect: $0, comic: false) } == [.classic, .classic, .classic, .classic])
        #expect((1...4).map { click.burst(forEffect: $0, comic: true) } == [.classic, .classic, .classic, .classic])
    }

    // MARK: Round trip

    @Test func wandAndClickSurviveEncoding() throws {
        let original = try skin(extra: """
        , "wand": {"color": "#C8CCD2", "width": 9, "style": "stick"},
        "click": {"bursts": ["ring"], "weight": 2}
        """)
        let decoded = try JSONDecoder().decode(Skin.self, from: JSONEncoder().encode(original))
        #expect(decoded.wand == original.wand)
        #expect(decoded.click == original.click)
    }

    // MARK: Fast exit

    @Test func effectsAreQuick() {
        #expect(Mood.burstDuration <= 0.3)
        for level in Mood.range {
            let style = Mood.style(level)
            #expect(style.lingerDuration <= 0.35)
            #expect(style.jabDuration <= 0.3)
        }
    }

    // MARK: Registry

    @Test func unknownDesignFallsBackToTheFirstRegistered() throws {
        var registry = SkinRegistry(skins: [])
        #expect(registry.skinOrFirst(id: "catpaw") == .classic)
        try registry.register(Skin.pocket)
        try registry.register(Skin.classic)
        #expect(registry.skinOrFirst(id: "catpaw") == .pocket)
        #expect(registry.skinOrFirst(id: "classic") == .classic)
    }
}
