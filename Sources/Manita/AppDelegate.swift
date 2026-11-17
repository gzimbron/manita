import AppKit
import ManitaCore

/// Composition root: owns state and wires the pieces together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PreferencesStore()
    private var registry = SkinRegistry.appDefault()
    private var preferences = Preferences.default
    /// Rapid presses: the jab and burst only play from the third one.
    private var streak = ClickStreak()

    private let overlay = OverlayController()
    private let sound = SoundPlayer()
    private let cursorHider = SystemCursorHider()
    private let mouse = MouseMonitor()
    private let hotkeys = HotkeyCenter()
    private let recorder = ShortcutRecorder()
    private let disarmer = ClickDisarmer()
    private let notice = PresentationNotice()
    private var menu: StatusMenuController!

    /// The shortcuts currently registered with the system, to skip needless re-registration.
    private var registeredHotkeys: [HotkeyCenter.Action: Hotkey] = [:]
    private var lastToggle: [HotkeyCenter.Action: TimeInterval] = [:]
    /// While the Record Shortcut window is open the shortcuts stay off, so pressing one records it.
    private var isRecordingShortcut = false
    private var appearanceObservation: NSKeyValueObservation?

    /// `~/Library/Application Support/Manita/Skins` — drop design folders (SVG) or `*.json` designs here.
    static var skinsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Manita/Skins", directoryHint: .isDirectory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = store.load()
        reloadSkins()

        menu = StatusMenuController(
            preferences: { [unowned self] in preferences },
            skins: { [unowned self] in registry.skins },
            isPresenting: { [unowned self] in disarmer.isActive },
            update: { [unowned self] change in update(change) },
            actions: .init(
                reloadSkins: { [unowned self] in reloadSkins(); apply() },
                togglePointer: { [unowned self] in toggle(.togglePointer) },
                togglePresentation: { [unowned self] in toggle(.togglePresentation) },
                recordShortcut: { [unowned self] target in recordShortcut(for: target) }
            )
        )

        mouse.onMove = { [unowned self] point in
            overlay.move(to: point)
            reassertCursorIfDue()
        }
        observeCursorResets()
        mouse.onButton = { [unowned self] isDown in handleButton(isDown: isDown) }
        mouse.start()

        // In presentation mode clicks never reach the monitors above; the disarmer reports them instead.
        disarmer.onButton = { [unowned self] isDown in handleButton(isDown: isDown) }
        hotkeys.onAction = { [unowned self] action in toggle(action) }
        // Designs draw their light or dark variant: redraw when macOS switches.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }

        apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        disarmer.stop()
        hotkeys.unregisterAll()
        cursorHider.setHidden(false)
    }

    private func update(_ change: (inout Preferences) -> Void) {
        change(&preferences)
        preferences = preferences.clamped()
        store.save(preferences)
        apply()
    }

    private var lastCursorReassert = Date.distantPast

    /// Other apps re-show the pointer when they change it; re-hide at most ~4×/s while moving.
    private func reassertCursorIfDue() {
        let now = Date()
        guard now.timeIntervalSince(lastCursorReassert) > 0.5 else { return }
        lastCursorReassert = now
        cursorHider.reassert()
    }

    private func observeCursorResets() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cursorHider.reassert() }
            }
        }
    }

    private func handleButton(isDown: Bool) {
        guard preferences.isEnabled else { return }
        // Presses reported by the presentation-mode disarmer count too: both paths end here.
        if isDown { streak.press(at: ProcessInfo.processInfo.systemUptime) }
        if preferences.clickAnimationEnabled {
            // Every press bounces; rapid streaks bounce a little higher.
            overlay.setPressed(isDown, strength: isDown ? max(1, streak.intensity) : nil,
                               bursts: isDown && streak.playsEffects(from: preferences.effectsFromClick),
                               shake: isDown && streak.playsEffects(from: max(preferences.effectsFromClick, 3)))
        }
        if isDown, preferences.soundEnabled {
            sound.playClick()
        }
    }

    /// Pushes the current preferences into every component.
    private func apply() {
        // A removed or unknown design (say "catpaw", saved earlier) falls back to the first one: the Glove.
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let design = registry.skinOrFirst(id: preferences.skinID)
        let skin = design.resolved(for: isDark ? .dark : .light, scheme: preferences.colorSchemes[design.id])
        overlay.configure(skin: skin, scale: preferences.scale, showArm: preferences.showArm,
                          mood: Mood.style(preferences.mood))
        overlay.setVisible(preferences.isEnabled)
        sound.volume = preferences.volume
        cursorHider.setHidden(preferences.isEnabled && preferences.hideSystemCursor)
        registerHotkeys()
        // Clicks must never stay disarmed without a visible pointer or a way out.
        if disarmer.isActive, !preferences.isEnabled || !hotkeys.isRegistered(.togglePresentation) {
            stopPresentation()
        }
        menu.rebuild()
    }

    private func reloadSkins() {
        registry = SkinRegistry.appDefault()
        let dir = Self.skinsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (file, error) in registry.loadSkins(in: dir) {
            NSLog("Manita: skipped invalid skin %@: %@", file.lastPathComponent, String(describing: error))
        }
    }

    // MARK: - Shortcuts

    private func registerHotkeys(force: Bool = false) {
        let wanted: [HotkeyCenter.Action: Hotkey] = [
            .togglePointer: preferences.pointerHotkey,
            .togglePresentation: preferences.presentationHotkey,
        ]
        guard !isRecordingShortcut, force || wanted != registeredHotkeys else { return }
        registeredHotkeys = wanted
        for action in hotkeys.register(wanted) {
            NSLog("Manita: could not register shortcut %@ (already in use?)", wanted[action]?.display ?? "")
            // Not remembered as registered, so the next settings change tries again.
            registeredHotkeys[action] = nil
        }
    }

    /// Runs a shortcut's action, from the hotkey or from its menu item.
    private func toggle(_ action: HotkeyCenter.Action) {
        // With the menu open, one key press arrives both as a menu key equivalent and as a hotkey.
        // Uptime, not the wall clock: a clock set backwards must never block the presentation exit.
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastToggle[action], now - last < 0.3 { return }
        lastToggle[action] = now
        switch action {
        case .togglePointer: update { $0.isEnabled.toggle() }
        case .togglePresentation: disarmer.isActive ? stopPresentation() : startPresentation()
        }
    }

    private func recordShortcut(for target: ShortcutTarget) {
        let others = ShortcutTarget.allCases.filter { $0 != target }
        // Recording switches the shortcuts off, and presentation mode must never be left without its exit.
        stopPresentation()
        defer {
            // Free the shortcuts so pressing a current one records it instead of triggering it.
            // After `record`: replacing an open recording runs its completion, which re-registers them.
            hotkeys.unregisterAll()
            registeredHotkeys = [:]
            isRecordingShortcut = true
        }
        recorder.record(
            actionName: target.title, current: hotkey(for: target),
            validate: { [unowned self] candidate in
                others.first { hotkey(for: $0).conflicts(with: candidate) }.map { "Already used by \($0.title)" }
            },
            completion: { [unowned self] recorded in
                isRecordingShortcut = false
                if let recorded {
                    update {
                        switch target {
                        case .pointer: $0.pointerHotkey = recorded
                        case .presentation: $0.presentationHotkey = recorded
                        }
                    }
                }
                registerHotkeys(force: true)
                menu.rebuild()
            }
        )
    }

    private func hotkey(for target: ShortcutTarget) -> Hotkey {
        switch target {
        case .pointer: preferences.pointerHotkey
        case .presentation: preferences.presentationHotkey
        }
    }

    // MARK: - Presentation mode

    /// Disarms clicks so the pointer can be used to call out details without pressing anything.
    /// Never persisted: the app always launches with working clicks.
    private func startPresentation() {
        // The shortcut is the only way out (menu clicks are swallowed too), so it must work first.
        // Retry a registration that failed earlier: the app that held the shortcut may be gone.
        if !hotkeys.isRegistered(.togglePresentation) { registerHotkeys(force: true) }
        guard hotkeys.isRegistered(.togglePresentation) else {
            alert("Presentation mode needs its shortcut",
                  "\(preferences.presentationHotkey.display) could not be registered, probably because another app uses it. "
                    + "Choose a different one in Shortcuts, then try again.")
            return
        }
        guard ClickDisarmer.hasPermission(prompt: false), disarmer.start() else {
            let open = alert("Manita needs Accessibility permission",
                             "To hold back clicks in presentation mode, allow Manita in "
                                + "System Settings › Privacy & Security › Accessibility, then try again.",
                             action: "Open System Settings")
            if open, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if !preferences.isEnabled {
            update { $0.isEnabled = true }
        }
        notice.showEntered(exitShortcut: preferences.presentationHotkey)
        menu.rebuild()
    }

    private func stopPresentation() {
        guard disarmer.isActive else { return }
        disarmer.stop()
        // A press swallowed just before stopping is still reported afterwards; release the hand after it.
        DispatchQueue.main.async { [overlay] in overlay.setPressed(false) }
        notice.showExited()
        menu.rebuild()
    }

    /// Shows a modal alert; returns true when the user picked `action`.
    @discardableResult
    private func alert(_ title: String, _ text: String, action: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let action {
            alert.addButton(withTitle: action)
            alert.addButton(withTitle: "Cancel")
        }
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn && action != nil
    }
}
