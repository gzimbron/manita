import Foundation
import Testing
@testable import ManitaCore

@Suite("Preferences")
struct PreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let name = "manita.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsEnableEverything() {
        let prefs = Preferences.default
        #expect(prefs.isEnabled)
        #expect(prefs.soundEnabled)
        #expect(prefs.clickAnimationEnabled)
        #expect(prefs.skinID == Skin.cartoon.id)
    }

    @Test func storeRoundTripsChanges() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        var prefs = store.load()
        prefs.soundEnabled = false
        prefs.clickAnimationEnabled = false
        prefs.volume = 0.25
        store.save(prefs)
        #expect(PreferencesStore(defaults: defaults).load() == prefs)
    }

    @Test func corruptDataFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: PreferencesStore.key)
        #expect(PreferencesStore(defaults: defaults).load() == .default)
    }

    @Test func decodesDataSavedBeforeNewerFieldsExisted() throws {
        let old = #"{"isEnabled":false,"soundEnabled":true,"clickAnimationEnabled":true,"volume":0.5,"scale":2,"skinID":"pocket"}"#
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
        #expect(prefs.isEnabled == false)
        #expect(prefs.skinID == "pocket")
        #expect(prefs.hideSystemCursor == Preferences.default.hideSystemCursor)
        #expect(prefs.showArm == Preferences.default.showArm)
    }

    @Test func showArmOffPersistsThroughStore() {
        let defaults = makeDefaults()
        var prefs = PreferencesStore(defaults: defaults).load()
        prefs.showArm = false
        PreferencesStore(defaults: defaults).save(prefs)
        #expect(PreferencesStore(defaults: defaults).load().showArm == false)
    }

    @Test func outOfRangeValuesAreClamped() {
        var prefs = Preferences.default
        prefs.volume = 3
        prefs.scale = 99
        let clamped = prefs.clamped()
        #expect(clamped.volume == 1)
        #expect(clamped.scale == Preferences.scaleRange.upperBound)
    }
}

@Suite("Skins")
struct SkinTests {
    @Test func builtInSkinsAreValid() throws {
        for skin in SkinRegistry.builtIns {
            try skin.validate()
        }
    }

    @Test func rendersTransparentAndColoredPixels() throws {
        let skin = Skin(
            id: "t", name: "T",
            palette: ["#": "#000000", "w": "#FFFFFF80"],
            frames: [.idle: ["#.", ".w"]],
            hotspot: .init(x: 0, y: 0)
        )
        let image = try skin.image(for: .idle)
        #expect(image.width == 2 && image.height == 2)
        #expect(image.pixel(x: 0, y: 0) == RGBA(r: 0, g: 0, b: 0, a: 255))
        #expect(image.pixel(x: 1, y: 0) == nil)
        #expect(image.pixel(x: 1, y: 1) == RGBA(r: 255, g: 255, b: 255, a: 128))
    }

    @Test func missingFrameFallsBackToIdle() throws {
        let skin = Skin(id: "t", name: "T", palette: ["#": "#000000"],
                        frames: [.idle: ["#"]], hotspot: .init(x: 0, y: 0))
        #expect(try skin.image(for: .pressed) == skin.image(for: .idle))
    }

    @Test func rejectsRaggedRows() {
        let skin = Skin(id: "t", name: "T", palette: ["#": "#000000"],
                        frames: [.idle: ["##", "#"]], hotspot: .init(x: 0, y: 0))
        #expect(throws: SkinError.raggedRows(frame: .idle)) { try skin.validate() }
    }

    @Test func rejectsUnknownPaletteSymbol() {
        let skin = Skin(id: "t", name: "T", palette: ["#": "#000000"],
                        frames: [.idle: ["#x"]], hotspot: .init(x: 0, y: 0))
        #expect(throws: SkinError.unknownSymbol("x", frame: .idle)) { try skin.validate() }
    }

    @Test func rejectsHotspotOutsideFrame() {
        let skin = Skin(id: "t", name: "T", palette: ["#": "#000000"],
                        frames: [.idle: ["#"]], hotspot: .init(x: 3, y: 0))
        #expect(throws: SkinError.hotspotOutOfBounds) { try skin.validate() }
    }

    @Test func registryLoadsJSONSkinAndFallsBack() throws {
        let json = """
        {"id":"mini","name":"Mini","palette":{"#":"#112233"},
         "frames":{"idle":["#"]},"hotspot":{"x":0,"y":0}}
        """
        var registry = SkinRegistry()
        let skin = try registry.register(json: Data(json.utf8))
        #expect(skin.id == "mini")
        #expect(registry.skin(id: "mini") == skin)
        #expect(registry.skin(id: "does-not-exist") == .classic)
    }

    @Test func defaultSkinIsTheBundledCartoon() {
        #expect(Preferences.default.skinID == "cartoon")
        #expect(Skin.cartoon.id == "cartoon")
        #expect(Preferences.default.showArm)
    }

    @Test func pixelSkinWithoutFramesIsRejected() {
        let json = ##"{"id":"x","name":"X"}"##
        var registry = SkinRegistry()
        #expect(throws: (any Error).self) { try registry.register(json: Data(json.utf8)) }
    }

    @Test func pixelSkinWithoutHotspotIsRejected() {
        var r = SkinRegistry()
        #expect(throws: (any Error).self) {
            try r.register(json: Data(##"{"id":"h","name":"H","palette":{"#":"#000000"},"frames":{"idle":["#"]}}"##.utf8))
        }
    }

    @Test func removedVectorKindIsRejectedAsPixelDesignWithoutPalette() {
        var r = SkinRegistry()
        #expect(throws: (any Error).self) {
            try r.register(json: Data(##"{"id":"ink","name":"Ink","vector":{"fill":"#FFFFFF","outline":"#000000","cuff":"#EEEEEE"}}"##.utf8))
        }
        #expect(r.skin(id: "ink") == .classic)
    }

    @Test func pixelSkinsRoundTripThroughJSON() throws {
        for s in [Skin.classic, .pocket] {
            #expect(try JSONDecoder().decode(Skin.self, from: JSONEncoder().encode(s)) == s)
        }
    }

    @Test func registryRejectsInvalidJSONSkin() {
        let json = ##"{"id":"bad","name":"Bad","palette":{},"frames":{"idle":["#"]},"hotspot":{"x":0,"y":0}}"##
        var registry = SkinRegistry()
        #expect(throws: SkinError.self) { try registry.register(json: Data(json.utf8)) }
        #expect(registry.skin(id: "bad") == .classic)
    }
}

@Suite("RetroSound")
struct RetroSoundTests {
    @Test func samplesStayWithinVolume() {
        let samples = RetroSound.click.samples(sampleRate: 44_100, volume: 0.5)
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { abs($0) <= 0.5 + 1e-6 })
    }

    @Test func zeroVolumeIsSilent() {
        #expect(RetroSound.click.samples(sampleRate: 44_100, volume: 0).allSatisfy { $0 == 0 })
    }

    @Test func wavHeaderIsValid() {
        let samples: [Float] = [0, 0.5, -0.5]
        let data = RetroSound.wavData(samples: samples, sampleRate: 22_050)
        #expect(data.count == 44 + samples.count * 2)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
    }
}

@Suite("CursorOverride")
struct CursorOverrideTests {
    @Test func namesCoverArrowIBeamAndLinkHand() {
        let names = CursorOverride.allNames
        #expect(names.contains("com.apple.coregraphics.Arrow"))
        #expect(names.contains("com.apple.coregraphics.IBeam"))
        #expect(names.contains("com.apple.cursor.2"))   // Link (pointing hand)
        #expect(names.contains("com.apple.cursor.13"))  // Pointing
        #expect(names.count == 9 + 42)
    }

    @Test func namesAreUnique() {
        #expect(Set(CursorOverride.allNames).count == CursorOverride.allNames.count)
    }

    @Test func transparentImageIsAllZeroAndSized() {
        let spec = TransparentCursorSpec.standard
        #expect(spec.pixelSize == 32)
        #expect(spec.bytesPerRow == 128)
        #expect(spec.pixels.count == 32 * 128)
        #expect(spec.pixels.allSatisfy { $0 == 0 })
        #expect(spec.frameCount == 1)
    }

    @Test func specClampsDegenerateInput() {
        #expect(TransparentCursorSpec(pointSize: 0, scale: -3).pixelSize == 1)
    }

    @Test func fallbackChainPrefersReplaceThenHideThenVisible() {
        #expect(CursorOverride.chooseMode(replaceAvailable: true, hideAvailable: true) == .transparentCursor)
        #expect(CursorOverride.chooseMode(replaceAvailable: false, hideAvailable: true) == .hideCursor)
        #expect(CursorOverride.chooseMode(replaceAvailable: false, hideAvailable: false) == .visible)
    }

    @Test func everyOverriddenNameHasARestoreStrategy() {
        for name in CursorOverride.allNames {
            for saved in [true, false] {
                let plan = CursorOverride.plan(for: name, originalSaved: saved)
                if plan.override { #expect(plan.restore != .notOverridden, "\(name) saved=\(saved)") }
                else { #expect(plan.restore == .notOverridden, "\(name) saved=\(saved)") }
            }
        }
    }

    @Test func coreGraphicsNamesAreOnlyOverriddenWhenOriginalIsSaved() {
        for name in CursorOverride.coreGraphicsNames {
            let saved = CursorOverride.plan(for: name, originalSaved: true)
            #expect(saved.override && saved.restore == .reRegisterOriginal)
            let unsaved = CursorOverride.plan(for: name, originalSaved: false)
            #expect(!unsaved.override && unsaved.restore == .notOverridden)
        }
    }

    @Test func numberedNamesAreRestoredBySystemReset() {
        for n in CursorOverride.numberedRange {
            for saved in [true, false] {
                let plan = CursorOverride.plan(for: "com.apple.cursor.\(n)", originalSaved: saved)
                #expect(plan.override && plan.restore == .systemReset)
            }
        }
    }

    @Test func unknownNamesAreNeverOverridden() {
        let plan = CursorOverride.plan(for: "com.example.other", originalSaved: true)
        #expect(!plan.override && plan.restore == .notOverridden)
    }

    @Test func overrideTookOnlyWhenImageIsFullyTransparent() {
        #expect(CursorOverride.overrideTook(opaquePixels: 233) == false)
        #expect(CursorOverride.overrideTook(opaquePixels: 1) == false)
        #expect(CursorOverride.overrideTook(opaquePixels: 0) == true)
    }

    @Test func leftoverDetectionMatchesOnlyManitaTransparentImage() {
        #expect(CursorOverride.looksLikeLeftover(pointSize: 16, opaquePixels: 0))
        #expect(!CursorOverride.looksLikeLeftover(pointSize: 16, opaquePixels: 5))
        #expect(!CursorOverride.looksLikeLeftover(pointSize: 28, opaquePixels: 0))
    }
}

@Suite("SVG skins")
struct SVGSkinTests {
    static let svg100 = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 80"><path d="M0 0h10v10z"/></svg>"#
    static let manifest = ##"{"id":"s","name":"S","svg":{"idle":"idle.svg","pressed":"pressed.svg"},"hotspot":{"x":40.5,"y":4},"armAnchor":{"x":50,"y":78},"armWidth":30,"arm":"#112233"}"##

    private func makeFolder(manifest: String = manifest, files: [String: String] = ["idle.svg": svg100, "pressed.svg": svg100]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "manita-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: dir.appending(path: "skin.json"))
        for (name, text) in files { try Data(text.utf8).write(to: dir.appending(path: name)) }
        return dir
    }

    @Test func manifestDecodesSVGFields() throws {
        let skin = try JSONDecoder().decode(Skin.self, from: Data(Self.manifest.utf8))
        #expect(skin.svg?.idle == "idle.svg")
        #expect(skin.svg?.pressed == "pressed.svg")
        #expect(skin.svgHotspot == SVGPoint(x: 40.5, y: 4))
        #expect(skin.svgArmAnchor == SVGPoint(x: 50, y: 78))
        #expect(skin.svgArmWidth == 30)
        #expect(skin.arm == "#112233")
    }

    @Test func folderLoadsAndValidates() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        let skin = try registry.register(manifestAt: dir)
        #expect(skin.svgViewBox == SVGRect(x: 0, y: 0, width: 100, height: 80))
        #expect(skin.svgData[.idle] != nil && skin.svgData[.pressed] != nil)
        #expect(registry.skin(id: "s") == skin)
        #expect(throws: SkinError.notPixelArt) { try skin.image(for: .idle) }
    }

    @Test func manifestFileCanBePassedDirectly() throws {
        let dir = try makeFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(try registry.register(manifestAt: dir.appending(path: "skin.json")).id == "s")
    }

    @Test func missingSVGFileIsRejected() throws {
        let dir = try makeFolder(files: ["idle.svg": Self.svg100])
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(throws: SkinError.missingSVGFile("pressed.svg")) { try registry.register(manifestAt: dir) }
        #expect(registry.skin(id: "s") == .classic)
    }

    @Test func pressedIsOptional() throws {
        let dir = try makeFolder(manifest: Self.manifest.replacingOccurrences(of: #","pressed":"pressed.svg""#, with: ""),
                                 files: ["idle.svg": Self.svg100])
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        let skin = try registry.register(manifestAt: dir)
        #expect(skin.svgData[.pressed] == nil)
    }

    @Test func hotspotOutsideViewBoxIsRejected() throws {
        let dir = try makeFolder(manifest: Self.manifest.replacingOccurrences(of: #""x":40.5,"y":4"#, with: #""x":101,"y":4"#))
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(throws: SkinError.hotspotOutOfBounds) { try registry.register(manifestAt: dir) }
    }

    @Test func armAnchorOutsideViewBoxIsRejected() throws {
        let dir = try makeFolder(manifest: Self.manifest.replacingOccurrences(of: #""y":78"#, with: #""y":-1"#))
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(throws: SkinError.armAnchorOutOfBounds) { try registry.register(manifestAt: dir) }
    }

    @Test func armColorMustBeHex() throws {
        let dir = try makeFolder(manifest: Self.manifest.replacingOccurrences(of: "#112233", with: "red"))
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(throws: SkinError.invalidColor("arm: red")) { try registry.register(manifestAt: dir) }
    }

    @Test func fileNamesCannotEscapeTheFolder() throws {
        let dir = try makeFolder(manifest: Self.manifest.replacingOccurrences(of: "idle.svg", with: "../idle.svg"))
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(throws: SkinError.invalidSVGPath("../idle.svg")) { try registry.register(manifestAt: dir) }
    }

    @Test func nonSVGContentIsRejected() throws {
        let dir = try makeFolder(files: ["idle.svg": "<html/>", "pressed.svg": Self.svg100])
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(throws: SkinError.invalidSVG("idle.svg")) { try registry.register(manifestAt: dir) }
    }

    @Test func viewBoxFallsBackToWidthAndHeight() throws {
        let box = try SVGDocument.parse(Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48px"/>"#.utf8)).viewBox
        #expect(box == SVGRect(x: 0, y: 0, width: 64, height: 48))
    }

    @Test func svgWithoutSizeIsRejected() {
        #expect(throws: (any Error).self) { try SVGDocument.parse(Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8)) }
    }

    @Test func pressedWithDifferentViewBoxIsRejected() throws {
        let other = Self.svg100.replacingOccurrences(of: "0 0 100 80", with: "0 0 90 80")
        let dir = try makeFolder(files: ["idle.svg": Self.svg100, "pressed.svg": other])
        defer { try? FileManager.default.removeItem(at: dir) }
        var registry = SkinRegistry()
        #expect(throws: SkinError.viewBoxMismatch) { try registry.register(manifestAt: dir) }
    }

    @Test func svgSkinRoundTripsThroughJSON() throws {
        let skin = try JSONDecoder().decode(Skin.self, from: Data(Self.manifest.utf8))
        #expect(try JSONDecoder().decode(Skin.self, from: JSONEncoder().encode(skin)) == skin)
    }

    @Test func loadSkinsReadsFoldersAndFlatJSONAndReportsBadOnes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "manita-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let good = try makeFolder()
        let bad = try makeFolder(manifest: Self.manifest.replacingOccurrences(of: #""id":"s""#, with: #""id":"b""#), files: [:])
        defer { try? FileManager.default.removeItem(at: good); try? FileManager.default.removeItem(at: bad) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: good, to: root.appending(path: "good"))
        try FileManager.default.moveItem(at: bad, to: root.appending(path: "bad"))
        try Data(##"{"id":"flat","name":"F","palette":{"#":"#000000"},"frames":{"idle":["#"]},"hotspot":{"x":0,"y":0}}"##.utf8)
            .write(to: root.appending(path: "flat.json"))
        var registry = SkinRegistry()
        let failures = registry.loadSkins(in: root)
        #expect(failures.count == 1)
        #expect(failures.first?.0.lastPathComponent == "bad")
        #expect(registry.skin(id: "s").svg != nil)
        #expect(registry.skin(id: "flat").id == "flat")
        #expect(registry.skin(id: "b") == .classic)
    }

    @Test func bundledCartoonIsValid() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var registry = SkinRegistry()
        let skin = try registry.register(manifestAt: repo.appending(path: "Resources/Skins/cartoon"))
        #expect(skin.id == "cartoon")
        #expect(skin.svgData[.idle] != nil && skin.svgData[.pressed] != nil)
    }
}
