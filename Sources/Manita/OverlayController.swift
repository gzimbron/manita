import AppKit
import ManitaCore
import QuartzCore

/// One static, transparent, click-through panel per display (`PointerSurface`), each with its own
/// copy of the pointer (sleeve + hand) and of the click bursts:
///
/// - moving the pointer only changes a layer position on the displays the hand touches, so a hand
///   near the edge between two displays is drawn in two parts, one per display, and never vanishes;
/// - bursts are dropped where a click lands and stay there while they play, so the hand can move on;
/// - displays the pointer is not near are ordered out and cost nothing.
///
/// How bold the sleeve is and how hard a click lands come from `MoodStyle`.
@MainActor
final class OverlayController {
    /// Sleeve direction: down and slightly to the right, like a cartoon arm reaching in.
    private static let armAngle: CGFloat = .pi / 9           // 20° from vertical

    /// Classic burst square, in hand heights: the website's 190 px burst around a 120 px hand.
    fileprivate static let classicSideInHands: CGFloat = 190.0 / 120.0

    /// How much bigger than the default mood's this mood's bursts are.
    private static func moodBurstRatio(_ mood: MoodStyle) -> CGFloat {
        CGFloat(mood.burstRadius / Mood.style(Mood.default).burstRadius)
    }

    /// One per `NSScreen`; rebuilt when the display configuration changes.
    private var surfaces: [PointerSurface] = []
    /// Window-less surface used to draw the preview and report its layout.
    private let preview = PointerSurface(screen: nil)
    private var spec: PointerSpec?
    private var screenObserver: NSObjectProtocol?

    private var artwork: HandArtwork?
    private var style = Mood.style(Mood.default)
    private var click = ClickConfig()
    /// The design's click art (`click.svg`), drawn once per `configure` at the largest size it plays.
    private var burstArt: [String: CGImage] = [:]
    /// Effects played so far; picks the burst kind and tells a newer click from an older one.
    private var clickCount = 0
    private var isVisible = false
    /// Bumped by every effect: a delayed clean-up only runs when no newer effect started.
    private var effectGeneration = 0
    private var lastPoint = NSPoint(x: CGFloat.nan, y: .nan)

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildSurfaces() }
        }
    }

    /// - Parameter skin: the design already resolved for the current appearance (`Skin.resolved(for:)`).
    func configure(skin: Skin, scale: Int, showArm: Bool, mood: MoodStyle) {
        guard let art = HandArtwork.render(skin, scale: scale) ?? HandArtwork.render(.classic, scale: scale)
        else { return }
        artwork = art
        style = mood
        click = art.click
        let wandInk = art.wandColor
        let effectInk = art.outline
        let maxStrength = CGFloat(ClickStreak.maxIntensity)

        let hand = max(art.size.width, art.size.height)
        let armLength = hand * mood.armLengthInHands
        let armWidth = art.armWidth * mood.armWidthScale
        let direction = CGVector(dx: sin(Self.armAngle), dy: -cos(Self.armAngle))
        // Room around the hotspot for the jab, the shake and the trail.
        let margin = hand * (0.5 + (mood.jabDistance + mood.shakeDistance) * maxStrength)
        let size = CGSize(width: margin * 2 + art.size.width + armLength * direction.dx + armWidth,
                          height: margin * 2 + art.size.height - armLength * direction.dy + armWidth)
        // Effects: sized for the largest burst this mood draws.
        let radius = hand * mood.burstRadius
        let lineWidth = max(1.5, hand * 0.035) * mood.burstWeight * CGFloat(click.weight)
        // Click art: a square `click.size` hands wide (scaled like the classic burst by the mood),
        // drawn at the strongest click's size; the effects square fits it turned and fully grown.
        let artSide = Self.artSide(click: click, hand: hand, mood: mood, strength: maxStrength)
        burstArt = [:]
        for name in click.svg ?? [] where burstArt[name] == nil {
            guard let data = skin.assetData[name],
                  let image = Self.renderArt(data, side: artSide, scale: art.contentsScale,
                                             tint: click.tint ? effectInk : nil)
            else { continue }
            burstArt[name] = image
        }
        let artReach = burstArt.isEmpty ? 0
            : artSide * CGFloat(max(click.animation.from, click.animation.to)) * 1.42
        spec = PointerSpec(
            art: art, mood: mood, showArm: showArm, wandInk: wandInk, effectInk: effectInk,
            size: size, margin: margin,
            hotspot: CGPoint(x: margin + art.hotspot.x, y: size.height - margin - art.hotspot.y),
            direction: direction, armLength: armLength, armWidth: armWidth,
            effectsSide: max((radius * maxStrength * 1.25 + lineWidth) * 2,
                             hand * Self.classicSideInHands * Self.moodBurstRatio(mood) * maxStrength * 1.2,
                             artReach),
            burstRadius: radius, burstLineWidth: lineWidth)
        rebuildSurfaces()
    }

    /// Creates one surface per screen and gives each its own copy of the pointer.
    private func rebuildSurfaces() {
        clearEffects()
        surfaces.forEach { $0.tearDown() }
        surfaces = NSScreen.screens.map { PointerSurface(screen: $0) }
        guard let spec else { return }
        withoutAnimation {
            for surface in surfaces + [preview] {
                surface.isEnabled = isVisible
                surface.apply(spec)
            }
        }
        lastPoint = NSPoint(x: CGFloat.nan, y: .nan)
        move(to: NSEvent.mouseLocation)
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if !visible { clearEffects() }
        withoutAnimation {
            for surface in surfaces {
                surface.isEnabled = visible
                surface.refresh()
            }
        }
    }

    func move(to point: NSPoint) {
        let target = NSPoint(x: point.x.rounded(), y: point.y.rounded())
        // Skip events that land on the same point.
        guard target != lastPoint else { return }
        lastPoint = target
        withoutAnimation {
            for surface in surfaces { surface.place(hotspot: target) }
        }
    }

    /// Shows the pressed frame while a button is down. A non-nil `strength` also lands the click
    /// (jab + burst): `1` is the mood's own strength, larger values hit harder (see `ClickStreak`).
    /// - Parameter bursts: also play the background bursts (a rapid click streak).
    /// - Parameter shake: jab and shake with a trail instead of the simple bounce.
    func setPressed(_ pressed: Bool, strength: Double? = nil, bursts: Bool = false, shake: Bool = false) {
        guard let art = artwork else { return }
        // The hand keeps its idle artwork: the bounce alone shows the click.
        withoutAnimation {
            for surface in surfaces { surface.pointer.hand.contents = art.idle }
        }
        guard pressed, let strength, isVisible else { return }
        let hand = max(art.size.width, art.size.height)
        clickCount += 1
        if shake {
            playJab(hand: hand, strength: CGFloat(strength))
        } else {
            playBounce(hand: hand, strength: CGFloat(strength))
        }
        guard bursts else { return }
        effectGeneration += 1
        let burstEnd = playBurst(at: NSEvent.mouseLocation, hand: hand, strength: CGFloat(strength))
        scheduleCleanup(burstEnd: burstEnd, jab: shake)
    }

    // MARK: - Click animation

    /// The hand and its sleeve hop up and to the left (where the finger points) and spring back
    /// with a small, damped overshoot. No bursts or trails: the bounce is the whole effect.
    private func playBounce(hand: CGFloat, strength: CGFloat) {
        let forward = CGVector(dx: -sin(Self.armAngle), dy: cos(Self.armAngle))
        let hop = hand * style.jabDistance * strength
        // Out, back past rest, a smaller hop, then settle exactly at rest.
        let steps: [CGFloat] = [0, 1, -0.3, 0.12, 0]
        func track(_ keyPath: String, _ axis: CGFloat) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = steps.map { $0 * hop * axis }
            animation.keyTimes = [0, 0.28, 0.6, 0.82, 1]
            animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                         CAMediaTimingFunction(name: .easeInEaseOut),
                                         CAMediaTimingFunction(name: .easeInEaseOut),
                                         CAMediaTimingFunction(name: .easeIn)]
            return animation
        }
        let group = CAAnimationGroup()
        group.animations = [track("transform.translation.x", forward.dx), track("transform.translation.y", forward.dy)]
        group.duration = 0.28 + 0.12 * Double(strength - 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for surface in surfaces {
            surface.pointer.root.instanceCount = 1
            surface.pointer.body.add(group, forKey: "jab")
        }
        CATransaction.commit()
    }

    /// The hand lunges at the click point and shakes back, like knocking on the screen.
    /// Same keyframes as the website: along the finger axis 0, 1.4, -0.25, 1.3, -0.25, 0.9, -0.1, 0
    /// times the hop, with a sideways shake alternating +-7% of the hand, over 280 ms.
    private func playJab(hand: CGFloat, strength: CGFloat) {
        // Forward is where the finger points: up the sleeve. Sideways is across it.
        let forward = CGVector(dx: -sin(Self.armAngle), dy: cos(Self.armAngle))
        let sideways = CGVector(dx: cos(Self.armAngle), dy: sin(Self.armAngle))
        let hop = hand * 0.12 * CGFloat(style.jabDistance / Mood.style(Mood.default).jabDistance) * strength
        let shake = hand * 0.07 * strength
        let steps: [CGFloat] = [0, 1.4, -0.25, 1.3, -0.25, 0.9, -0.1, 0]

        var xs: [CGFloat] = [], ys: [CGFloat] = []
        for (index, step) in steps.enumerated() {
            let edge = index == 0 || index == steps.count - 1
            let across = edge ? 0 : (index % 2 == 1 ? 1 : -1) * shake
            xs.append(forward.dx * step * hop + sideways.dx * across)
            ys.append(forward.dy * step * hop + sideways.dy * across)
        }

        func track(_ keyPath: String, _ values: [CGFloat]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.timingFunctions = values.dropFirst().map { _ in CAMediaTimingFunction(name: .easeOut) }
            return animation
        }
        let group = CAAnimationGroup()
        group.animations = [track("transform.translation.x", xs), track("transform.translation.y", ys)]
        group.duration = Self.jabDuration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for surface in surfaces {
            // Two trailing faded copies, 45 ms apart.
            surface.pointer.root.instanceCount = 3
            surface.pointer.body.add(group, forKey: "jab")
        }
        CATransaction.commit()
    }

    /// Seconds a jab takes (the website's 280 ms), and how long its last trailing copy takes to finish.
    private static let jabDuration = 0.28
    private static let jabTotal = jabDuration + 2 * PointerSurface.trailDelay

    /// Lays the burst of `kind` into one surface's layers. Caller disables implicit animations.
    private func shapeBurst(on surface: PointerSurface, kind: BurstKind, hand: CGFloat, strength: CGFloat, seed: Int) {
        guard let spec else { return }
        if kind == .classic {
            // The web look is part of the design: rays and star fill keep the design's accent whatever
            // the Color setting says; only the star outline (ink) follows it.
            let accent = artwork?.outline ?? spec.effectInk
            surface.burstLayer.strokeColor = accent
            surface.starLayer.fillColor = accent
            let unit = hand * Self.classicSideInHands * Self.moodBurstRatio(style) * strength / 100
            // Every click turns and resizes the splash and drops the star somewhere new.
            var rng = SplitMix(seed: UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 97))
            let splash = CGAffineTransform(translationX: effectsCenter.x, y: effectsCenter.y)
                .rotated(by: rng.next(in: 0...(2 * .pi)))
                .scaledBy(x: rng.next(in: 0.8...1.2), y: rng.next(in: 0.8...1.2))
                .translatedBy(x: -effectsCenter.x, y: -effectsCenter.y)
            let starOffset = CGPoint(x: rng.next(in: -12...12) * unit, y: rng.next(in: -12...12) * unit)
            let starSpin = CGAffineTransform(translationX: effectsCenter.x + starOffset.x, y: effectsCenter.y + starOffset.y)
                .rotated(by: rng.next(in: -0.6...0.6))
                .scaledBy(x: rng.next(in: 0.85...1.15), y: rng.next(in: 0.85...1.15))
                .translatedBy(x: -effectsCenter.x, y: -effectsCenter.y)
            surface.burstLayer.path = BurstShape.classicRays(unit: unit, center: effectsCenter).copy(using: [splash])
            surface.burstLayer.lineWidth = 4 * unit * CGFloat(click.weight)
            surface.starLayer.path = BurstShape.classicStar(unit: unit, center: effectsCenter).copy(using: [starSpin])
            surface.starLayer.lineWidth = 2 * unit * CGFloat(click.weight)
        } else {
            surface.burstLayer.strokeColor = spec.effectInk
            surface.burstLayer.path = burstPath(kind: kind, radius: hand * style.burstRadius * strength, seed: seed)
            surface.burstLayer.lineWidth = spec.burstLineWidth
            surface.starLayer.path = nil
        }
    }

    /// Side of the click art square, in points, for a click of `strength`.
    private static func artSide(click: ClickConfig, hand: CGFloat, mood: MoodStyle, strength: CGFloat) -> CGFloat {
        hand * CGFloat(click.size) * moodBurstRatio(mood) * strength
    }

    /// Draws click art SVG into a square image of `side` points, aspect ratio kept and centered.
    /// With `tint` its shapes become a mask filled with that color.
    private static func renderArt(_ data: Data, side: CGFloat, scale: CGFloat, tint: CGColor?) -> CGImage? {
        guard let box = try? SVGDocument.parse(data).viewBox, box.width > 0, box.height > 0 else { return nil }
        let fit = side / CGFloat(max(box.width, box.height))
        let size = CGSize(width: CGFloat(box.width) * fit, height: CGFloat(box.height) * fit)
        guard let image = HandArtwork.rasterize(data, size: size, backingScale: scale) else { return nil }
        let pixels = Int((side * scale).rounded(.up))
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.draw(image, in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                   width: size.width, height: size.height))
        if let tint {
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(tint)
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return ctx.makeImage()
    }

    /// Lays this click's art into one surface: sized for `strength`, turned when `spin` is on.
    /// - Returns: `false` when the design has no art for this effect (the `bursts` presets play instead).
    @discardableResult
    private func shapeArt(on surface: PointerSurface, slot: Int, effect: Int, hand: CGFloat, strength: CGFloat) -> Bool {
        let art = surface.artBursts[slot]
        guard let name = click.art(forEffect: effect), let image = burstArt[name] else {
            art.image.contents = nil
            return false
        }
        let side = Self.artSide(click: click, hand: hand, mood: style, strength: strength)
        var rng = SplitMix(seed: UInt64(truncatingIfNeeded: effect &* 2654435761 &+ 31))
        surface.burstLayer.path = nil
        surface.starLayer.path = nil
        art.layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        art.image.frame = art.layer.bounds
        art.image.contents = image
        art.image.contentsGravity = .resizeAspect
        let limit = CGFloat(click.animation.rotation) * .pi / 180
        art.image.setAffineTransform(
            click.animation.spin && limit > 0 ? CGAffineTransform(rotationAngle: rng.next(in: -limit...limit)) : .identity)
        return true
    }

    /// - Returns: seconds the burst (and its linger, if any) takes.
    @discardableResult
    private func playBurst(at point: NSPoint, hand: CGFloat, strength: CGFloat) -> TimeInterval {
        if click.art(forEffect: clickCount) != nil, !burstArt.isEmpty {
            return playArt(at: point, hand: hand, strength: strength)
        }
        let kind = click.burst(forEffect: clickCount, comic: style.comicBursts)
        // Every display gets the burst at the click point; only the one holding it shows anything.
        withoutAnimation {
            for surface in surfaces {
                surface.placeEffects(at: point)
                shapeBurst(on: surface, kind: kind, hand: hand, strength: strength, seed: clickCount)
            }
        }

        let classic = kind == .classic
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = classic ? 0.4 : 0.55
        grow.toValue = classic ? 1.15 : 1.1
        let fade: CAAnimation
        if classic {
            let linear = CABasicAnimation(keyPath: "opacity")
            linear.fromValue = 1
            linear.toValue = 0
            fade = linear
        } else {
            let steps = CAKeyframeAnimation(keyPath: "opacity")
            steps.values = [1, 1, 0]
            steps.keyTimes = [0, 0.6, 1]
            fade = steps
        }
        let burst = CAAnimationGroup()
        burst.animations = [grow, fade]
        burst.duration = classic ? Mood.classicBurstDuration : Mood.burstDuration
        burst.timingFunction = CAMediaTimingFunction(name: .easeOut)
        for surface in surfaces {
            surface.burstLayer.add(burst, forKey: "burst")
            if classic { surface.starLayer.add(burst, forKey: "burst") }
            surface.lingerLayer.removeAnimation(forKey: "linger")
        }

        // The website's burst has no trailing ring.
        guard !classic, style.lingerDuration > 0 else { return burst.duration }
        let linger = CAKeyframeAnimation(keyPath: "opacity")
        linger.values = [0, 0.55, 0.45, 0]
        linger.keyTimes = [0, 0.15, 0.6, 1]
        linger.beginTime = CACurrentMediaTime() + burst.duration * 0.6
        linger.duration = min(style.lingerDuration, Mood.maxLingerDuration)
        for surface in surfaces { surface.lingerLayer.add(linger, forKey: "linger") }
        return burst.duration * 0.6 + linger.duration
    }

    /// Plays the design's click art with its `click.animation`. - Returns: seconds it takes.
    private func playArt(at point: NSPoint, hand: CGFloat, strength: CGFloat) -> TimeInterval {
        let animation = click.animation
        // Each click takes the next slot, so up to `artSlots` effects play at once, each to its end.
        let slot = clickCount % PointerSurface.artSlots
        // Scatter: a random point within `scatter` hand sizes of the click (uniform over the circle).
        var rng = SplitMix(seed: UInt64(truncatingIfNeeded: clickCount &* 40503 &+ 7))
        let reach = hand * CGFloat(animation.scatter) * sqrt(rng.next(in: 0...1))
        let angle = rng.next(in: 0...(2 * .pi))
        let landing = NSPoint(x: point.x + cos(angle) * reach, y: point.y + sin(angle) * reach)
        withoutAnimation {
            for surface in surfaces {
                surface.placeEffects(at: landing, slot: slot)
                shapeArt(on: surface, slot: slot, effect: clickCount, hand: hand, strength: strength)
            }
        }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = animation.from
        grow.toValue = animation.to
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = animation.fade ? 0 : 1
        let burst = CAAnimationGroup()
        burst.animations = [grow, fade]
        burst.duration = animation.duration
        burst.timingFunction = CAMediaTimingFunction(name: .easeOut)
        for surface in surfaces {
            surface.artBursts[slot].layer.add(burst, forKey: "burst")
        }
        return animation.duration
    }

    private func burstPath(kind: BurstKind, radius: CGFloat, seed: Int) -> CGPath {
        switch kind {
        case .classic: BurstShape.classicRays(unit: radius / 50, center: effectsCenter)
        case .rays: BurstShape.rays(count: style.burstRays, radius: radius, length: 0.5, center: effectsCenter, seed: seed)
        case .star: BurstShape.star(points: style.burstRays - 4, radius: radius, center: effectsCenter, seed: seed)
        case .ring: BurstShape.ring(radius: radius, center: effectsCenter)
        }
    }

    /// After the last effect ends, leaves nothing behind: the panel goes away and the hand is at rest.
    /// A newer click bumps `effectGeneration`, so only the last effect's timer acts.
    private func scheduleCleanup(burstEnd: TimeInterval, jab: Bool) {
        let generation = effectGeneration
        let total = max(jab ? Self.jabTotal : 0.28, burstEnd) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.effectGeneration == generation else { return }
                self.clearEffects()
            }
        }
    }

    /// Stops every effect and hides the effects panel; the hand returns to its resting place.
    private func clearEffects() {
        effectGeneration += 1
        withoutAnimation {
            for surface in surfaces {
                surface.pointer.body.removeAnimation(forKey: "jab")
                surface.pointer.root.instanceCount = 1
                for layer in [surface.burstLayer, surface.starLayer, surface.lingerLayer] + surface.artBursts.map(\.layer) {
                    layer.removeAllAnimations()
                    layer.opacity = 0
                }
                surface.effectsRect = nil
                surface.refresh()
            }
        }
    }

    private var effectsCenter: CGPoint { spec?.effectsCenter ?? .zero }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: - Preview

    /// Draws the resting pointer and a burst into `context` (bottom-left origin), for `--render-preview`.
    func drawPreview(in context: CGContext, hotspot: CGPoint) {
        guard let art = artwork, let spec else { return }
        let hand = max(art.size.width, art.size.height)
        withoutAnimation {
            // The comic mood shows its second (star) effect; designs with their own list show the first.
            let effect = style.comicBursts ? 2 : 1
            if shapeArt(on: preview, slot: 0, effect: effect, hand: hand, strength: 1) {
                preview.artBursts[0].layer.opacity = 1
            } else {
                shapeBurst(on: preview, kind: click.burst(forEffect: effect, comic: style.comicBursts),
                           hand: hand, strength: 1, seed: effect)
                preview.burstLayer.opacity = 1
                preview.starLayer.opacity = 1
            }
        }
        context.saveGState()
        context.translateBy(x: hotspot.x - spec.effectsSide / 2, y: hotspot.y - spec.effectsSide / 2)
        preview.burstLayer.render(in: context)
        preview.starLayer.render(in: context)
        context.restoreGState()
        if preview.artBursts[0].layer.opacity > 0 {
            // The art is drawn at its own size (scale 1) around the click point, like the classic burst.
            let side = preview.artBursts[0].layer.bounds.width
            context.saveGState()
            context.translateBy(x: hotspot.x, y: hotspot.y)
            context.concatenate(preview.artBursts[0].image.affineTransform())
            context.translateBy(x: -side / 2, y: -side / 2)
            preview.artBursts[0].image.render(in: context)
            context.restoreGState()
        }
        context.saveGState()
        context.translateBy(x: hotspot.x - spec.hotspot.x, y: hotspot.y - spec.hotspot.y)
        preview.pointer.body.render(in: context)
        context.restoreGState()
        withoutAnimation {
            preview.burstLayer.opacity = 0
            preview.starLayer.opacity = 0
            preview.artBursts[0].layer.opacity = 0
        }
    }

    /// Size of the pointer layer tree and where the hotspot sits in it.
    var previewLayout: (size: CGSize, hotspot: CGPoint) { (CGSize(width: ceil(spec?.size.width ?? 0), height: ceil(spec?.size.height ?? 0)), spec?.hotspot ?? .zero) }
}

/// Click burst outlines, centered on the click point.
enum BurstShape {
    /// Straight rays around a circle; lengths vary with `seed` so no two clicks look stamped.
    /// - Parameter length: ray length as a share of `radius`.
    static func rays(count: Int, radius: CGFloat, length: CGFloat, center: CGPoint, seed: Int = 0) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<count {
            let angle = 2 * .pi * (CGFloat(i) + 0.5 * CGFloat(seed % 2)) / CGFloat(count)
            let outer = radius * (0.72 + 0.28 * jitter(i, seed))
            let inner = outer - radius * length * (0.6 + 0.4 * jitter(i + 7, seed))
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        }
        return path
    }

    /// The website's rays: 12 straight rays from 18 to 46 (even) or 36 (odd) units, `unit` points each.
    static func classicRays(unit: CGFloat, center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<12 {
            let angle = CGFloat(i) / 12 * 2 * .pi + 0.2
            let outer: CGFloat = i.isMultiple(of: 2) ? 46 : 36
            // The web's y axis points down, the layer's up.
            path.move(to: CGPoint(x: center.x + cos(angle) * 18 * unit, y: center.y - sin(angle) * 18 * unit))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer * unit, y: center.y - sin(angle) * outer * unit))
        }
        return path
    }

    /// The website's star: 10 points alternating radius 15 and 7 units, starting at the top.
    static func classicStar(unit: CGFloat, center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<10 {
            let angle = CGFloat(i) / 10 * 2 * .pi - .pi / 2
            let r: CGFloat = i % 2 == 1 ? 7 : 15
            let point = CGPoint(x: center.x + cos(angle) * r * unit, y: center.y - sin(angle) * r * unit)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// An expanding ring.
    static func ring(radius: CGFloat, center: CGPoint) -> CGPath {
        let r = radius * 0.85
        return CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)
    }

    /// A comic "pow" outline: a closed star with uneven spikes.
    static func star(points: Int, radius: CGFloat, center: CGPoint, seed: Int = 0) -> CGPath {
        let path = CGMutablePath()
        let corners = max(points, 5) * 2
        for i in 0..<corners {
            let angle = 2 * .pi * CGFloat(i) / CGFloat(corners) + .pi / 2
            let reach = i.isMultiple(of: 2) ? radius * (0.74 + 0.26 * jitter(i, seed)) : radius * 0.46
            let point = CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Deterministic pseudo-random value in `0...1`.
    private static func jitter(_ index: Int, _ seed: Int) -> CGFloat {
        let value = sin(CGFloat(index * 127 + seed * 311) * 12.9898) * 43758.5453
        return value - value.rounded(.down)
    }
}

extension PixelImage {
    func cgImage() -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (index, pixel) in pixels.enumerated() {
            guard let p = pixel else { continue }
            // Premultiplied alpha, as required by CGImageAlphaInfo.premultipliedLast.
            let alpha = UInt16(p.a)
            bytes[index * 4 + 0] = UInt8(UInt16(p.r) * alpha / 255)
            bytes[index * 4 + 1] = UInt8(UInt16(p.g) * alpha / 255)
            bytes[index * 4 + 2] = UInt8(UInt16(p.b) * alpha / 255)
            bytes[index * 4 + 3] = p.a
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Small deterministic random generator: the same click number gives the same splash on every display.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func next(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}
