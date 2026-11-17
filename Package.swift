// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Manita",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Manita", targets: ["Manita"])
    ],
    targets: [
        // Pure, UI-free logic: preferences, skins, sound synthesis. Fully unit-tested.
        .target(name: "ManitaCore"),
        // AppKit shell: menu bar, overlay window, event monitoring, audio playback.
        .executableTarget(name: "Manita", dependencies: ["ManitaCore", "ManitaSkins"]),
        // Bundled SVG designs (Resources/Skins/<id>/), exposed through Bundle.module.
        .target(name: "ManitaSkins", path: "Resources/Skins",
                sources: ["BuiltInSkins.swift"], resources: [.copy("cartoon"), .copy("magic-wand"), .copy("cat-paw")]),
        .testTarget(name: "ManitaCoreTests", dependencies: ["ManitaCore"]),
    ]
)
