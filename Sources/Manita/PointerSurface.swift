import AppKit
import ManitaCore
import QuartzCore

/// Everything a surface needs to build the pointer and its effects; computed once per `configure`.
struct PointerSpec {
    let art: HandArtwork
    let mood: MoodStyle
    let showArm: Bool
    let wandInk: CGColor
    let effectInk: CGColor
    /// Size of the pointer layer tree (hand + sleeve + room for the jab, shake and trail).
    let size: CGSize
    let margin: CGFloat
    /// Where the hotspot sits inside the pointer tree (bottom-left layer coordinates).
    let hotspot: CGPoint
    let direction: CGVector
    let armLength: CGFloat
    let armWidth: CGFloat
    let effectsSide: CGFloat
    let burstRadius: CGFloat
    let burstLineWidth: CGFloat

    var effectsCenter: CGPoint { CGPoint(x: effectsSide / 2, y: effectsSide / 2) }
}

/// The pointer layer tree: trail replicator → body → sleeve / stick + hand.
/// One instance per surface, all built and configured by the same `apply`.
@MainActor
final class PointerLayers {
    let root = CAReplicatorLayer()
    let body = CALayer()
    private let armLayer = CAGradientLayer()
    private let armMask = CAShapeLayer()
    /// The `stick` wand: filled segments and collars, optionally faded by `stickFade`.
    private let stickLayer = CAShapeLayer()
    private let stickFade = CAGradientLayer()
    /// The design's own sleeve (`wand.svg`): one strip image laid along the sleeve, faded by `artFade`.
    private let artLayer = CALayer()
    private let artFade = CAGradientLayer()
    let hand = CALayer()

    init() {
        hand.anchorPoint = .zero
        armMask.fillColor = nil
        armMask.lineCap = .butt
        armLayer.mask = armMask
        stickLayer.strokeColor = nil
        stickFade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        body.addSublayer(armLayer)
        body.addSublayer(stickLayer)
        artLayer.mask = artFade
        body.addSublayer(artLayer)
        body.addSublayer(hand)
        root.addSublayer(body)
        root.instanceDelay = PointerSurface.trailDelay
        root.instanceAlphaOffset = -0.4
    }

    /// Caller wraps this in a transaction with actions disabled.
    func apply(_ spec: PointerSpec) {
        let art = spec.art, mood = spec.mood, size = spec.size, margin = spec.margin
        let direction = spec.direction, armLength = spec.armLength, armWidth = spec.armWidth
        let bounds = CGRect(origin: .zero, size: size)
        root.bounds = bounds
        root.anchorPoint = .zero
        body.frame = bounds

        // Hand: top-left artwork coordinates into bottom-left layer coordinates.
        let origin = CGPoint(x: margin, y: size.height - margin - art.size.height)
        hand.frame = CGRect(origin: origin, size: art.size)
        hand.contents = art.idle
        hand.contentsScale = art.contentsScale
        hand.magnificationFilter = art.isPixelArt ? .nearest : .linear

        // Sleeve: a bar starting a little inside the cuff (the hand is drawn on top, so no gap shows).
        let anchor = CGPoint(x: origin.x + art.armAnchor.x, y: origin.y + art.size.height - art.armAnchor.y)
        let tuck = art.armWidth * 0.25
        let start = CGPoint(x: anchor.x - direction.dx * tuck, y: anchor.y - direction.dy * tuck)
        let end = CGPoint(x: start.x + direction.dx * armLength, y: start.y + direction.dy * armLength)
        let armPath = CGMutablePath()
        armPath.move(to: start)
        armPath.addLine(to: end)
        let isStick = art.wand.style == .stick
        let fades = art.wand.fades
        let fadeStart = CGPoint(x: start.x / size.width, y: start.y / size.height)
        let fadeEnd = CGPoint(x: end.x / size.width, y: end.y / size.height)
        let fadeLocations: [NSNumber] = fades ? [0, NSNumber(value: mood.armOpaqueFraction), 1] : [0, 1]

        // Sleeve: a gradient seen through the bar-shaped mask.
        let wandInk = spec.wandInk
        armLayer.frame = bounds
        armMask.frame = bounds
        armMask.path = armPath
        armMask.strokeColor = NSColor.black.cgColor
        armMask.lineWidth = armWidth
        let peak = wandInk.copy(alpha: wandInk.alpha * mood.armOpacity) ?? wandInk
        armLayer.colors = fades ? [peak, peak, wandInk.copy(alpha: 0) ?? wandInk] : [peak, peak]
        armLayer.locations = fadeLocations
        armLayer.startPoint = fadeStart
        armLayer.endPoint = fadeEnd
        let strip = spec.showArm
            ? art.sleeveStrip(width: armWidth, length: armLength, ink: wandInk) : nil
        let hasArt = art.sleeveTile != nil
        armLayer.isHidden = !spec.showArm || isStick || hasArt

        // Design's sleeve: the strip hangs from `start` (top-center anchor), turned to the sleeve direction.
        artLayer.setAffineTransform(.identity)
        artLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
        artLayer.bounds = CGRect(x: 0, y: 0, width: armWidth, height: armLength)
        artLayer.position = start
        artLayer.setAffineTransform(CGAffineTransform(rotationAngle: atan2(direction.dx, -direction.dy)))
        artLayer.contents = strip
        artLayer.contentsScale = art.contentsScale
        artLayer.opacity = Float(mood.armOpacity)
        artFade.frame = artLayer.bounds
        artFade.startPoint = CGPoint(x: 0.5, y: 1)
        artFade.endPoint = CGPoint(x: 0.5, y: 0)
        artFade.locations = fadeLocations
        artFade.colors = fades
            ? [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            : [NSColor.black.cgColor, NSColor.black.cgColor]
        artLayer.isHidden = !spec.showArm || !hasArt

        // Stick: telescopic segments, thinner away from the hand, joined by collars.
        stickLayer.frame = bounds
        stickLayer.path = Self.stickPath(from: start, direction: direction, length: armLength, width: armWidth)
        stickLayer.fillColor = wandInk
        stickFade.frame = bounds
        stickFade.locations = fadeLocations
        stickFade.startPoint = fadeStart
        stickFade.endPoint = fadeEnd
        stickFade.colors = fades
            ? [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            : [NSColor.black.cgColor, NSColor.black.cgColor]
        stickLayer.mask = fades ? stickFade : nil
        stickLayer.isHidden = !spec.showArm || !isStick || hasArt
    }

    /// The telescopic pointer: three tube segments, each thinner than the last, with a collar at each joint.
    private static func stickPath(from start: CGPoint, direction d: CGVector, length: CGFloat, width: CGFloat) -> CGPath {
        let n = CGVector(dx: -d.dy, dy: d.dx)
        let path = CGMutablePath()
        func bar(_ from: CGFloat, _ to: CGFloat, _ w: CGFloat) {
            let half = w / 2
            let a = CGPoint(x: start.x + d.dx * from, y: start.y + d.dy * from)
            let b = CGPoint(x: start.x + d.dx * to, y: start.y + d.dy * to)
            path.addLines(between: [
                CGPoint(x: a.x + n.dx * half, y: a.y + n.dy * half), CGPoint(x: b.x + n.dx * half, y: b.y + n.dy * half),
                CGPoint(x: b.x - n.dx * half, y: b.y - n.dy * half), CGPoint(x: a.x - n.dx * half, y: a.y - n.dy * half),
            ])
            path.closeSubpath()
        }
        let widths: [CGFloat] = [1, 0.68, 0.46].map { $0 * width }
        let joints: [CGFloat] = [0.36, 0.69, 1]
        var from: CGFloat = 0
        for (index, joint) in joints.enumerated() {
            let end = length * joint
            bar(from, end, widths[index])
            if index < joints.count - 1 {
                // The collar where one tube slides into the next.
                let collar = width * 0.5
                bar(end - collar / 2, end + collar / 2, widths[index] * 1.4)
            }
            from = end
        }
        return path
    }
}

/// One static, full-screen, transparent, click-through panel for one display, with its own copy of
/// the pointer layers and the burst layers. The pointer is moved by changing a layer position, never
/// the window, and each display draws only its part of the hand and sleeve, so nothing vanishes when
/// the pointer is near the edge between two displays. A surface with nothing to draw is ordered out.
///
/// With `screen == nil` the surface has no window; it only holds layers (used by `--render-pointer`).
@MainActor
final class PointerSurface {
    /// Delay between the hand and each faded copy trailing it during a jab.
    static let trailDelay: CFTimeInterval = 0.045

    /// The display's frame in global coordinates.
    let frame: CGRect
    let pointer = PointerLayers()
    /// Rays (stroke only) or the single outline of the older burst kinds.
    let burstLayer = CAShapeLayer()
    /// The classic burst's filled, outlined star; drawn above the rays, empty for other kinds.
    let starLayer = CAShapeLayer()
    let lingerLayer = CAShapeLayer()
    /// How many click art effects can play at once; rapid clicks take the slots in turn, so each one
    /// plays to its end instead of cutting the previous one short.
    static let artSlots = 5
    /// The design's own click art (`click.svg`), one pair per slot: `layer` plays the animation,
    /// `image` holds the picture turned to that click's angle.
    let artBursts: [(layer: CALayer, image: CALayer)] = (0..<PointerSurface.artSlots).map { _ in (CALayer(), CALayer()) }
    private let panel: NSPanel?
    private let canvas: CALayer
    private(set) var spec: PointerSpec?
    /// Whether the pointer is shown at all.
    var isEnabled = false
    /// Global rect of the burst being played; `nil` when no effect is active.
    var effectsRect: CGRect?
    private var hotspot = CGPoint.zero
    private var isShown = false

    init(screen: NSScreen?) {
        if let screen {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false, screen: screen)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            let view = NSView()
            view.wantsLayer = true
            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            self.panel = panel
            canvas = view.layer ?? CALayer()
            frame = screen.frame
        } else {
            panel = nil
            canvas = CALayer()
            frame = .zero
        }
        for layer in [burstLayer, starLayer, lingerLayer] {
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.opacity = 0
            canvas.addSublayer(layer)
        }
        for art in artBursts {
            art.layer.opacity = 0
            art.layer.addSublayer(art.image)
            canvas.addSublayer(art.layer)
        }
        // The hand is drawn above its own burst.
        canvas.addSublayer(pointer.root)
    }

    /// Builds the pointer and effects layers from `spec`. Caller disables implicit animations.
    func apply(_ spec: PointerSpec) {
        self.spec = spec
        pointer.apply(spec)
        let side = spec.effectsSide
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        for layer in [burstLayer, starLayer, lingerLayer] {
            layer.bounds = bounds
            layer.strokeColor = spec.effectInk
        }
        // Classic star: accent fill, ink outline.
        starLayer.fillColor = spec.effectInk
        starLayer.strokeColor = spec.wandInk
        burstLayer.lineWidth = spec.burstLineWidth
        lingerLayer.lineWidth = max(1, spec.burstLineWidth * 0.55)
        lingerLayer.path = BurstShape.rays(count: max(8, spec.mood.burstRays - 2), radius: spec.burstRadius * 0.62,
                                           length: 0.28, center: spec.effectsCenter)
        place(hotspot: hotspot)
    }

    /// Moves the pointer to a global hotspot. Caller wraps this in a transaction with actions disabled.
    func place(hotspot: CGPoint) {
        self.hotspot = hotspot
        guard let spec else { return }
        // Layer coordinates are bottom-left, like the screen's own.
        let origin = CGPoint(x: (hotspot.x - spec.hotspot.x).rounded(), y: (hotspot.y - spec.hotspot.y).rounded())
        let intersects = isEnabled && CGRect(origin: origin, size: spec.size).intersects(frame)
        pointer.root.isHidden = !intersects
        if intersects {
            pointer.root.position = CGPoint(x: origin.x - frame.minX, y: origin.y - frame.minY)
        }
        updateWindow(needed: intersects)
    }

    /// Centers the burst layers on a global click point, in this display's coordinates.
    /// - Parameter slot: also (only) moves that click art slot; the other slots keep playing where they are.
    func placeEffects(at point: CGPoint, slot: Int? = nil) {
        guard let spec else { return }
        let side = spec.effectsSide
        let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        // Effects still playing elsewhere keep the window up: the rect grows to hold them all.
        effectsRect = effectsRect.map { $0.union(rect) } ?? rect
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        if let slot {
            artBursts[slot].layer.position = local
        } else {
            for layer in [burstLayer, starLayer, lingerLayer] { layer.position = local }
        }
        place(hotspot: hotspot)
    }

    /// Re-evaluates the window after `isEnabled` or `effectsRect` changed.
    func refresh() { place(hotspot: hotspot) }

    private func updateWindow(needed: Bool) {
        guard let panel else { return }
        let show = needed || (effectsRect?.intersects(frame) ?? false)
        guard show != isShown else { return }
        isShown = show
        if show { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    /// Removes the window for good (the display went away or the surfaces are rebuilt).
    func tearDown() {
        panel?.orderOut(nil)
        isShown = false
    }
}
