import AppKit
import ManitaCore

/// Private CoreGraphics cursor registration, resolved with `dlsym` (no private linking).
/// Signatures come from Mousecape's CGSInternal/CGSCursor.h and apply.m/restore.m.
/// See docs/adr/0005-replace-system-cursors.md.
final class TransparentCursorBackend: @unchecked Sendable {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias Register = @convention(c) (
        Int32, UnsafeMutablePointer<CChar>, Bool, Bool, CGSize, CGPoint, UInt, CGFloat, CFArray, UnsafeMutablePointer<Int32>
    ) -> Int32
    private typealias UnregisterAll = @convention(c) (Int32) -> Int32
    private typealias CursorSet = @convention(c) (Int32, Int32) -> Int32

    private let connection: MainConnection
    private let register: Register
    private let unregisterAll: UnregisterAll
    private let cursorSet: CursorSet
    private let lock = NSLock()
    private var applied = false

    /// nil when any private symbol is missing.
    init?() {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let c = dlsym(handle, "CGSMainConnectionID"),
              let r = dlsym(handle, "CGSRegisterCursorWithImages"),
              let u = dlsym(handle, "CoreCursorUnregisterAll"),
              let s = dlsym(handle, "CoreCursorSet")
        else { return nil }
        connection = unsafeBitCast(c, to: MainConnection.self)
        register = unsafeBitCast(r, to: Register.self)
        unregisterAll = unsafeBitCast(u, to: UnregisterAll.self)
        cursorSet = unsafeBitCast(s, to: CursorSet.self)
    }

    var isApplied: Bool { lock.lock(); defer { lock.unlock() }; return applied }

    private static func transparentImage(_ spec: TransparentCursorSpec) -> CGImage? {
        var pixels = spec.pixels
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: spec.pixelSize, height: spec.pixelSize,
                bitsPerComponent: 8, bytesPerRow: spec.bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }

    /// Registers the transparent cursor under every system cursor name.
    /// Returns false (after restoring) if the Arrow could not be replaced.
    func apply() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let spec = TransparentCursorSpec.standard
        guard let image = Self.transparentImage(spec) else { return false }
        let images = [image] as CFArray
        let cid = connection()
        var arrowOK = false
        for name in CursorOverride.allNames {
            var seed: Int32 = 0
            var cName = Array(name.utf8CString)
            let err = cName.withUnsafeMutableBufferPointer { buf in
                register(cid, buf.baseAddress!, true, true,
                         CGSize(width: spec.pointSize, height: spec.pointSize),
                         CGPoint(x: spec.hotSpot.x, y: spec.hotSpot.y),
                         UInt(spec.frameCount), CGFloat(spec.frameDuration), images, &seed)
            }
            if name == "com.apple.coregraphics.Arrow" { arrowOK = (err == 0) }
        }
        if !arrowOK { restoreLocked(); return false }
        applied = true
        return true
    }

    /// Mousecape's reset: unregister all, then re-select the 45 core cursors.
    func restore() { lock.lock(); defer { lock.unlock() }; restoreLocked() }

    private func restoreLocked() {
        let cid = connection()
        if unregisterAll(cid) == 0 {
            for id in 0..<45 { _ = cursorSet(cid, Int32(id)) }
        }
        applied = false
    }
}

private let sharedCursorBackend: TransparentCursorBackend? = TransparentCursorBackend()

/// Free functions (not main-actor isolated) so they may run on any thread at exit/signal time.
private func restoreCursorsAtExit() {
    if let backend = sharedCursorBackend, backend.isApplied { backend.restore() }
}

private func terminationSignalHandler() {
    restoreCursorsAtExit()
    exit(0)
}

/// Keeps the macOS pointer out of sight while Manita draws the hand.
///
/// Preferred: replace every system cursor with a transparent image (Mousecape
/// technique), which survives other apps setting their cursor. Fallbacks:
/// `CGDisplayHideCursor` + "SetsCursorInBackground", then leaving it visible.
/// See docs/adr/0005-replace-system-cursors.md (supersedes the mechanism of 0003).
@MainActor
final class SystemCursorHider {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static var backend: TransparentCursorBackend? { sharedCursorBackend }
    private static var signalSources: [any DispatchSourceSignal] = []

    private var isHidden = false
    /// True while this process holds one `CGDisplayHideCursor` (balanced by one show on release).
    private var displayHidden = false
    private var mode: CursorOverride.Mode = .visible
    private var lastApply = Date.distantPast
    private lazy var backgroundEnabled: Bool = enableBackgroundCursorControl()

    init() {
        Self.installExitSafetyNets()
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        if hidden {
            if let backend = Self.backend, backend.apply() {
                mode = .transparentCursor
                lastApply = Date()
            } else {
                mode = backgroundEnabled ? .hideCursor : .visible
            }
            // macOS ignores the transparent image for the Arrow (and IBeam): hide the pointer as well,
            // and let the transparent images cover the cursors other apps switch to.
            hideDisplayCursor()
            NSLog("Manita: system pointer mode = %@", mode.rawValue)
        } else {
            release()
        }
        isHidden = hidden
    }

    /// macOS may reset or re-show cursors when other apps change theirs.
    func reassert() {
        guard isHidden else { return }
        // Re-register the ~50 transparent images rarely: app switches already trigger it, and it is costly.
        if Date().timeIntervalSince(lastApply) > 10 {
            lastApply = Date()
            if mode == .transparentCursor, Self.backend?.apply() != true {
                mode = backgroundEnabled ? .hideCursor : .visible
                NSLog("Manita: cursor override lost; falling back to %@", mode.rawValue)
            }
        }
        // Other apps re-show the pointer when they set theirs; a balanced show/hide hides it again.
        if displayHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            hideDisplayCursor()
        }
    }

    private func hideDisplayCursor() {
        guard !displayHidden, backgroundEnabled else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        displayHidden = true
    }

    private func release() {
        if mode == .transparentCursor { Self.backend?.restore() }
        if displayHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            displayHidden = false
        }
        mode = .visible
    }

    // MARK: - Exit safety nets

    /// Restores cursors if Manita is killed with SIGTERM/SIGINT/SIGHUP or exits via `exit()`.
    /// A crash or SIGKILL cannot be intercepted; see README "Known limitations".
    private static func installExitSafetyNets() {
        guard signalSources.isEmpty, backend != nil else { return }
        atexit(restoreCursorsAtExit)
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            // Global queue: still fires if the main thread is busy.
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global(qos: .userInitiated))
            source.setEventHandler(handler: terminationSignalHandler)
            source.resume()
            signalSources.append(source)
        }
    }

    private func enableBackgroundCursorControl() -> Bool {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connSym = dlsym(handle, "_CGSDefaultConnection"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty")
        else { return false }
        let connection = unsafeBitCast(connSym, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSym, to: SetProperty.self)
        return setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }
}
