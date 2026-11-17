import AppKit
import ManitaCore
import ServiceManagement

/// The two actions that own a global shortcut.
enum ShortcutTarget: CaseIterable {
    case pointer
    case presentation

    var title: String {
        switch self {
        case .pointer: "Show/Hide Pointer"
        case .presentation: "Presentation Mode"
        }
    }
}

/// The menu bar icon and its settings menu. Stateless: every rebuild reads
/// the current preferences; every action sends a change back through `update`.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    typealias Change = (inout Preferences) -> Void

    /// What the menu can ask the app to do besides changing a preference.
    struct Actions {
        var reloadSkins: () -> Void = {}
        var togglePointer: () -> Void = {}
        var togglePresentation: () -> Void = {}
        var recordShortcut: (ShortcutTarget) -> Void = { _ in }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let preferences: () -> Preferences
    private let skins: () -> [Skin]
    private let isPresenting: () -> Bool
    private let update: (Change) -> Void
    private let actions: Actions

    private var isOpen = false
    private var needsRebuild = false

    init(preferences: @escaping () -> Preferences, skins: @escaping () -> [Skin],
         isPresenting: @escaping () -> Bool = { false },
         update: @escaping (Change) -> Void, actions: Actions = Actions()) {
        self.preferences = preferences
        self.skins = skins
        self.isPresenting = isPresenting
        self.update = update
        self.actions = actions
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "hand.point.up.left.fill",
                                           accessibilityDescription: "Manita")
    }

    func rebuild() {
        // Replacing the menu while it is open would close it under the mood slider.
        guard !isOpen else {
            needsRebuild = true
            return
        }
        let prefs = preferences()
        let menu = NSMenu()
        menu.delegate = self

        let pointer = action(prefs.isEnabled ? "Hide Pointer" : "Show Pointer") { [actions] in actions.togglePointer() }
        show(prefs.pointerHotkey, on: pointer)
        menu.addItem(pointer)
        let presentation = action("Presentation Mode") { [actions] in actions.togglePresentation() }
        presentation.state = isPresenting() ? .on : .off
        show(prefs.presentationHotkey, on: presentation)
        menu.addItem(presentation)

        menu.addItem(.separator())
        let mood = NSMenuItem()
        mood.view = MoodSliderView(level: prefs.mood) { [update, preferences] level in
            // The slider reports every drag event; only a new stop is a change.
            guard level != preferences().mood else { return }
            update { $0.mood = level }
        }
        menu.addItem(mood)

        // Design ▸: every design (a design with two or more color schemes opens a submenu of them;
        // picking one selects the design and that scheme), then the designs folder actions.
        // An unknown saved design shows as the first, an unknown saved scheme as the design's first.
        menu.addItem(.separator())
        let designs = skins()
        let designMenu = NSMenu()
        let activeID = designs.contains { $0.id == prefs.skinID } ? prefs.skinID : designs.first?.id
        for skin in designs {
            let names = skin.schemeNames
            guard names.count > 1 else {
                designMenu.addItem(toggle(skin.name, activeID == skin.id) { $0.skinID = skin.id })
                continue
            }
            let saved = prefs.colorSchemes[skin.id] ?? ""
            let current = names.contains(saved) ? saved : names[0]
            let item = submenu(skin.name, options: names.map { name in
                let label = name == names[0] ? "\(name) (Default)" : name
                return (label, activeID == skin.id && current == name, { prefs in
                    prefs.skinID = skin.id
                    prefs.colorSchemes[skin.id] = name
                })
            })
            item.state = activeID == skin.id ? .on : .off
            designMenu.addItem(item)
        }
        if !designs.isEmpty { designMenu.addItem(.separator()) }
        designMenu.addItem(action("Open Designs Folder…") {
            NSWorkspace.shared.open(AppDelegate.skinsDirectory)
        })
        designMenu.addItem(action("Reload Designs") { [actions] in actions.reloadSkins() })
        let designItem = NSMenuItem(title: "Design", action: nil, keyEquivalent: "")
        designItem.submenu = designMenu
        menu.addItem(designItem)
        menu.addItem(submenu("Size", options: Preferences.scaleRange.map { s in
            ("\(Preferences.displaySize(forScale: s))×", prefs.scale == s, { $0.scale = s })
        }))

        menu.addItem(.separator())
        menu.addItem(toggle("Animate on Click", prefs.clickAnimationEnabled) { $0.clickAnimationEnabled.toggle() })
        menu.addItem(submenu("Effects From Click", options: Preferences.effectsFromClickRange.map { n in
            (n == 1 ? "Every Click" : "Click \(n) of a Streak", prefs.effectsFromClick == n, { $0.effectsFromClick = n })
        }))
        menu.addItem(toggle("Click Sound", prefs.soundEnabled) { $0.soundEnabled.toggle() })
        menu.addItem(submenu("Volume", options: [0.25, 0.5, 0.75, 1.0].map { v in
            ("\(Int(v * 100))%", abs(prefs.volume - v) < 0.01, { $0.volume = v })
        }))
        menu.addItem(toggle("Show Sleeve", prefs.showArm) { $0.showArm.toggle() })
        menu.addItem(toggle("Hide System Pointer", prefs.hideSystemCursor) { $0.hideSystemCursor.toggle() })

        menu.addItem(.separator())
        let shortcuts = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        shortcuts.submenu = NSMenu()
        for target in ShortcutTarget.allCases {
            let hotkey = target == .pointer ? prefs.pointerHotkey : prefs.presentationHotkey
            shortcuts.submenu?.addItem(action("\(target.title): \(hotkey.display)…") { [actions] in
                actions.recordShortcut(target)
            })
        }
        shortcuts.submenu?.addItem(.separator())
        shortcuts.submenu?.addItem(action("Reset to Defaults") { [update] in
            update {
                $0.pointerHotkey = .togglePointer
                $0.presentationHotkey = .presentationMode
            }
        })
        menu.addItem(shortcuts)
        let loginItem = action("Launch at Login") { [weak self] in self?.toggleLaunchAtLogin() }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(action("About Manita") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutCredits()])
        })
        menu.addItem(action("Quit Manita", key: "q") { NSApp.terminate(nil) })

        statusItem.menu = menu
    }

    /// About panel credits: a link to the source repository.
    private static func aboutCredits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString()
        let links = [
            ("GitHub: gzimbron/manita", "https://github.com/gzimbron/manita"),
        ]
        for (index, (title, url)) in links.enumerated() {
            if index > 0 { credits.append(NSAttributedString(string: "\n", attributes: base)) }
            var attributes = base
            attributes[.link] = URL(string: url)
            credits.append(NSAttributedString(string: title, attributes: attributes))
        }
        return credits
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        if needsRebuild {
            needsRebuild = false
            rebuild()
        }
    }

    // MARK: - Builders

    private func toggle(_ title: String, _ isOn: Bool, change: @escaping Change) -> NSMenuItem {
        let item = action(title) { [update] in update(change) }
        item.state = isOn ? .on : .off
        return item
    }

    private func submenu(_ title: String, options: [(String, Bool, Change)]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, selected, change) in options {
            sub.addItem(toggle(label, selected, change: change))
        }
        item.submenu = sub
        return item
    }

    private func action(_ title: String, key: String = "", _ handler: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
    }

    /// Draws the global shortcut next to the item, the way macOS shows key equivalents.
    private func show(_ hotkey: Hotkey, on item: NSMenuItem) {
        guard hotkey.key.count == 1 else {
            // Named keys (Space, F5…) have no key-equivalent glyph; spell the shortcut out.
            item.title += "  \(hotkey.display)"
            return
        }
        item.keyEquivalent = hotkey.key.lowercased()
        var mask: NSEvent.ModifierFlags = []
        if hotkey.modifiers.contains(.control) { mask.insert(.control) }
        if hotkey.modifiers.contains(.option) { mask.insert(.option) }
        if hotkey.modifiers.contains(.shift) { mask.insert(.shift) }
        if hotkey.modifiers.contains(.command) { mask.insert(.command) }
        item.keyEquivalentModifierMask = mask
    }

    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Manita: launch at login failed: %@", String(describing: error))
        }
        rebuild()
    }
}

/// The "Pointer Mood" row: a four-stop slider from a discreet finger to an unmissable one.
private final class MoodSliderView: NSView {
    private let onChange: (Int) -> Void

    init(level: Int, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 66))

        let title = Self.label("Pointer Mood", size: 13)
        let slider = NSSlider(value: Double(level), minValue: Double(Mood.range.lowerBound),
                              maxValue: Double(Mood.range.upperBound), target: self, action: #selector(changed))
        slider.numberOfTickMarks = Mood.range.count
        slider.allowsTickMarkValuesOnly = true
        slider.controlSize = .small
        let low = Self.label("Subtle", size: 10)
        let high = Self.label("Look at me!", size: 10)

        for view in [title, slider, low, high] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            slider.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            low.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            low.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            high.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            high.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func label(_ text: String, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func changed(_ sender: NSSlider) {
        onChange(Int(sender.doubleValue.rounded()))
    }
}

/// NSMenuItem that runs a closure, avoiding a selector per action.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
