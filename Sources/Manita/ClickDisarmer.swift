import AppKit

/// Presentation mode's engine: a session event tap that swallows mouse clicks so they never
/// reach any app, while still reporting them so the pointer can animate.
///
/// Button presses and releases are dropped. While a button is physically held the system
/// reports movement as a drag; those events are rewritten to plain `.mouseMoved` so no app sees
/// a drag without its mouse-down, and global mouse-move monitors keep following the pointer.
/// Everything else (scrolling, keys) is never tapped and passes through untouched.
@MainActor final class ClickDisarmer {
    /// Called for every swallowed button press (`true`) and release (`false`).
    var onButton: ((_ isDown: Bool) -> Void)?

    var isActive: Bool { tap.isInstalled }

    private let tap = DisarmTap()

    init() {
        tap.onButton = { [weak self] isDown in self?.onButton?(isDown) }
    }

    deinit {
        // Never leave clicks swallowed because the owner went away.
        tap.uninstall()
    }

    /// True when the process may create an active event tap (Accessibility permission).
    /// `prompt: true` asks macOS to show its permission dialog when it is missing.
    static func hasPermission(prompt: Bool) -> Bool {
        // Literal value of `kAXTrustedCheckOptionPrompt`; the global var is not concurrency-safe in Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Starts swallowing clicks. Returns false (and stays inactive) when the tap cannot be created.
    @discardableResult func start() -> Bool {
        tap.install()
    }

    func stop() {
        tap.uninstall()
    }
}

/// Owns the CoreGraphics tap. Kept apart from `ClickDisarmer` so `deinit` (nonisolated) can tear
/// it down, and so the C callback gets a stable pointer whose lifetime we control.
///
/// Thread rules: `install`, the tap callback and `onButton` run on the main thread (the tap's
/// source lives on the main run loop). `uninstall` is safe from any thread; off the main thread
/// the final release of the callback context is deferred to the main queue, so a callback that is
/// mid-flight there can never touch freed memory.
private final class DisarmTap: @unchecked Sendable {
    /// Main-thread only.
    var onButton: (@MainActor (_ isDown: Bool) -> Void)?

    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// The +1 reference handed to the tap as `userInfo`; released only after the tap is gone.
    private var retainedSelf: Unmanaged<DisarmTap>?

    var isInstalled: Bool {
        lock.lock(); defer { lock.unlock() }
        return port != nil
    }

    private static let mask: CGEventMask = {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        ]
        return types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
    }()

    func install() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if port != nil { return true }

        let context = Unmanaged.passRetained(self)
        guard let newPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                return Unmanaged<DisarmTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
            },
            userInfo: context.toOpaque()
        ) else {
            context.release()
            return false
        }
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newPort, 0) else {
            CFMachPortInvalidate(newPort)
            context.release()
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newPort, enable: true)
        port = newPort
        source = newSource
        retainedSelf = context
        return true
    }

    /// Removes the tap and its run-loop source. Idempotent.
    func uninstall() {
        lock.lock()
        let oldPort = port, oldSource = source, context = retainedSelf
        port = nil
        source = nil
        retainedSelf = nil
        lock.unlock()

        if let oldPort {
            CGEvent.tapEnable(tap: oldPort, enable: false)
            if let oldSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), oldSource, .commonModes) }
            CFMachPortInvalidate(oldPort)
        }
        guard let context else { return }
        if Thread.isMainThread {
            context.release()
        } else {
            let box = UnmanagedBox(context)
            DispatchQueue.main.async { box.value.release() }
        }
    }

    /// The tap callback. Runs on the main run loop; must stay short so macOS does not time the tap out.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            lock.lock()
            let current = port
            lock.unlock()
            // Only revive a tap that is still meant to be running.
            if let current { CGEvent.tapEnable(tap: current, enable: true) }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            report(true)
            return nil
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            report(false)
            return nil
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            event.type = .mouseMoved
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Delivered after the callback returns, so observers never run inside the tap and cannot
    /// re-enter it (e.g. by calling `stop()`). Every swallowed event is reported, even if the tap
    /// was removed in between, so a press is never left without its release.
    private func report(_ isDown: Bool) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { onButton?(isDown) }
        }
    }
}

/// Carries the tap's retained context across to the main queue for its final release.
private struct UnmanagedBox: @unchecked Sendable {
    let value: Unmanaged<DisarmTap>
    init(_ value: Unmanaged<DisarmTap>) { self.value = value }
}
