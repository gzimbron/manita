import AppKit

/// Observes pointer movement and button presses system-wide.
///
/// Global monitors see events delivered to other apps; local monitors cover our
/// own menu. Monitors are observe-only: they never block or alter clicks.
@MainActor
final class MouseMonitor {
    var onMove: ((NSPoint) -> Void)?
    var onButton: ((_ isDown: Bool) -> Void)?

    private var monitors: [Any] = []

    private static let moveMask: NSEvent.EventTypeMask =
        [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private static let downMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    private static let upMask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]

    func start() {
        stop()
        let mask = Self.moveMask.union(Self.downMask).union(Self.upMask)
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
        onMove?(NSEvent.mouseLocation)
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        // NSEvent.mouseLocation is in global screen coordinates (bottom-left origin).
        onMove?(NSEvent.mouseLocation)
        let type = NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)
        if Self.downMask.contains(type) { onButton?(true) }
        if Self.upMask.contains(type) { onButton?(false) }
    }
}
