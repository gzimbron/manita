import AppKit
import Carbon.HIToolbox
import ManitaCore

/// System-wide keyboard shortcuts, registered with Carbon `RegisterEventHotKey`
/// (works without Accessibility permission and while any app is frontmost).
@MainActor
final class HotkeyCenter {
    enum Action: UInt32, CaseIterable {
        case togglePointer = 1
        case togglePresentation = 2
    }

    var onAction: ((Action) -> Void)?

    /// 'MnTa': tags our hot keys so foreign IDs are ignored.
    private static let signature: OSType = 0x4D6E_5461

    private var handler: EventHandlerRef?
    private var registrations: [Action: EventHotKeyRef] = [:]

    init() {
        installHandler()
    }

    isolated deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Replaces every registration. Returns the actions whose shortcut could not be registered
    /// (for example, already taken by another app).
    @discardableResult
    func register(_ hotkeys: [Action: Hotkey]) -> Set<Action> {
        unregisterAll()
        var failed: Set<Action> = []
        for action in Action.allCases {
            guard let hotkey = hotkeys[action] else { continue }
            guard hotkey.isValid, let keyCode = UInt32(exactly: hotkey.keyCode) else {
                failed.insert(action)
                continue
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(keyCode, Self.carbonModifiers(hotkey.modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registrations[action] = ref
            } else {
                failed.insert(action)
            }
        }
        return failed
    }

    func unregisterAll() {
        for ref in registrations.values { UnregisterEventHotKey(ref) }
        registrations.removeAll()
    }

    func isRegistered(_ action: Action) -> Bool {
        // Without the event handler a registered shortcut would never reach `onAction`.
        handler != nil && registrations[action] != nil
    }

    // MARK: - Carbon

    private static func carbonModifiers(_ modifiers: Hotkey.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // Unretained: the handler is removed in deinit, before `self` goes away.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotkeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let rawID = id.id
            // Carbon dispatches application-target events on the main thread.
            MainActor.assumeIsolated {
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.handle(rawID)
            }
            return noErr
        }, 1, &spec, context, &handler)
        if status != noErr { handler = nil }
    }

    private func handle(_ rawID: UInt32) {
        guard let action = Action(rawValue: rawID), registrations[action] != nil else { return }
        onAction?(action)
    }
}
