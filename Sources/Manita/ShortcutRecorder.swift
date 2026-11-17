import AppKit
import ManitaCore

/// A small window that waits for the user to press a new shortcut.
@MainActor
final class ShortcutRecorder {
    private var session: RecordingSession?

    isolated deinit {
        session?.finish(nil)
    }

    /// - Parameters:
    ///   - actionName: e.g. "Show/Hide Pointer", shown in the prompt.
    ///   - current: the shortcut in use, shown as the starting value.
    ///   - validate: returns a user-facing problem (e.g. a conflict) or nil when the shortcut is acceptable.
    ///   - completion: the accepted shortcut, or nil when cancelled. Called exactly once.
    func record(actionName: String, current: Hotkey,
                validate: @escaping (Hotkey) -> String?, completion: @escaping (Hotkey?) -> Void) {
        session?.finish(nil)
        let session = RecordingSession(actionName: actionName, current: current,
                                       validate: validate, completion: completion)
        session.onFinish = { [weak self, weak session] in
            if let self, self.session === session { self.session = nil }
        }
        self.session = session
        session.start()
    }

    /// Builds a `Hotkey` from a key press: virtual key code, device-independent
    /// modifiers and an upper-case label.
    static func hotkey(from event: NSEvent) -> Hotkey {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Hotkey.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return Hotkey(keyCode: Int(event.keyCode), key: label(for: event), modifiers: modifiers)
    }

    private static let namedKeys: [UInt16: String] = [
        49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "Delete", 117: "Fwd Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func label(for event: NSEvent) -> String {
        if let name = namedKeys[event.keyCode] { return name }
        let characters = (event.charactersIgnoringModifiers ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return characters.isEmpty ? "Key \(event.keyCode)" : characters.uppercased()
    }
}

/// One open recording window. Owns the panel and the key monitor, and
/// guarantees both are torn down and `completion` runs exactly once.
@MainActor
private final class RecordingSession: NSObject, NSWindowDelegate {
    var onFinish: (() -> Void)?

    private let validate: (Hotkey) -> String?
    private var completion: ((Hotkey?) -> Void)?
    private var monitor: Any?
    private let panel: NSPanel
    private let caps = NSStackView()
    private let status = NSTextField(labelWithString: "")

    init(actionName: String, current: Hotkey,
         validate: @escaping (Hotkey) -> String?, completion: @escaping (Hotkey?) -> Void) {
        self.validate = validate
        self.completion = completion
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                        styleMask: [.titled, .closable], backing: .buffered, defer: true)
        super.init()

        panel.title = "Record Shortcut"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.delegate = self

        let prompt = NSTextField(wrappingLabelWithString: "Press the new shortcut for \(actionName)")
        prompt.alignment = .center
        prompt.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        caps.orientation = .horizontal
        caps.spacing = 4
        showCaps(for: current)

        status.alignment = .center
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 2
        status.stringValue = "Current: \(current.display)"

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = ""

        let stack = NSStackView(views: [prompt, caps, status, cancel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        prompt.widthAnchor.constraint(equalToConstant: 280).isActive = true
        status.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        panel.contentView = content
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handle(event)
            return nil
        }
        panel.layoutIfNeeded()
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Tears everything down and reports the result. Safe to call repeatedly;
    /// only the first call has an effect.
    func finish(_ result: Hotkey?) {
        guard let completion else { return }
        self.completion = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        panel.delegate = nil
        panel.close()
        onFinish?()
        onFinish = nil
        completion(result)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isDisjoint(with: [.control, .option, .shift, .command]) {
            finish(nil)
            return
        }
        let hotkey = ShortcutRecorder.hotkey(from: event)
        showCaps(for: hotkey)
        guard hotkey.isValid else {
            showProblem("Include ⌃, ⌥ or ⌘")
            return
        }
        if let problem = validate(hotkey) {
            showProblem(problem)
            return
        }
        finish(hotkey)
    }

    private func showProblem(_ text: String) {
        status.stringValue = text
        status.textColor = .systemRed
        NSSound.beep()
    }

    private func showCaps(for hotkey: Hotkey) {
        for view in caps.arrangedSubviews {
            caps.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for symbol in hotkey.modifierSymbols + [hotkey.key.uppercased()] where !symbol.isEmpty {
            caps.addArrangedSubview(Self.keyCap(symbol))
        }
    }

    private static func keyCap(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.cornerRadius = 5
        cap.layer?.borderWidth = 1
        cap.layer?.borderColor = NSColor.separatorColor.cgColor
        cap.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cap.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cap.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: cap.centerYAnchor),
            cap.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            cap.widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: 14),
            cap.heightAnchor.constraint(equalToConstant: 30),
        ])
        return cap
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    @objc private func cancelPressed() {
        finish(nil)
    }
}
