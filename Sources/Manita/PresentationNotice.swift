import AppKit
import ManitaCore
import QuartzCore

/// A transient, click-through notice shown when presentation mode turns on or off.
///
/// One borderless panel is reused: showing a notice replaces whatever is on screen. The card
/// appears on the screen holding the mouse, centered horizontally in its lower third.
@MainActor final class PresentationNotice {
    private static let width: CGFloat = 420
    private static let cornerRadius: CGFloat = 18
    private static let fadeIn: TimeInterval = 0.2
    private static let fadeOut: TimeInterval = 0.35

    private let panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        return panel
    }()

    private var hideTimer: Timer?
    /// Bumped on every show/dismiss so stale timers and fade completions do nothing.
    private var generation = 0

    /// Shows the "on" notice with the exit shortcut and a progress bar that empties over `duration`, then fades out.
    func showEntered(exitShortcut: Hotkey, duration: TimeInterval = 6) {
        let progress = ProgressBar()
        let card = Self.card(arranged: [
            Self.title("Presentation mode is on"),
            Self.body("Clicks are disarmed. Point and click anywhere to call out details — "
                + "nothing gets pressed, and your slides stay put."),
            Self.shortcutBox(exitShortcut),
            progress,
        ])
        present(card, duration: duration)
        progress.run(duration: duration)
    }

    /// Shows a brief "off" notice.
    func showExited(duration: TimeInterval = 1.8) {
        let card = Self.card(arranged: [
            Self.title("Presentation mode is off"),
            Self.body("Clicks work again."),
        ])
        present(card, duration: duration)
    }

    func dismiss() {
        generation += 1
        hideTimer?.invalidate()
        hideTimer = nil
        guard panel.isVisible else { return }
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A newer notice took over the panel while this one faded.
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    // MARK: - Presenting

    private func present(_ card: NSView, duration: TimeInterval) {
        generation += 1
        hideTimer?.invalidate()
        hideTimer = nil

        let wasVisible = panel.isVisible && panel.alphaValue > 0
        panel.contentView = card
        card.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: ceil(card.fittingSize.height))
        panel.setFrame(NSRect(origin: Self.origin(for: size), size: size), display: true)
        panel.invalidateShadow()

        if !wasVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            panel.animator().alphaValue = 1
        }

        let current = generation
        hideTimer = Timer.scheduledTimer(withTimeInterval: max(0, duration), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.hideTimer = nil
                self.dismiss()
            }
        }
    }

    /// Horizontally centered, card center at one third of the height, on the screen with the mouse.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let area = screen?.visibleFrame else { return .zero }
        return NSPoint(x: (area.midX - size.width / 2).rounded(),
                       y: (area.minY + area.height / 3 - size.height / 2).rounded())
    }

    // MARK: - Building the card

    private static func card(arranged views: [NSView]) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: cornerRadius)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 18, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if views.count > 2 { stack.setCustomSpacing(16, after: views[views.count - 2]) }
        effect.addSubview(stack)

        NSLayoutConstraint.activate([
            effect.widthAnchor.constraint(equalToConstant: width),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        // Wrapping text, the shortcut box and the progress bar span the content width.
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
        return effect
    }

    /// Resizable rounded-rect mask so the blurred material itself has rounded corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private static func title(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .center
        return label
    }

    private static func body(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.preferredMaxLayoutWidth = width - 48
        label.isSelectable = false
        return label
    }

    private static func shortcutBox(_ shortcut: Hotkey) -> NSView {
        let caption = NSTextField(labelWithString: "Press this shortcut to exit")
        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center

        let keys = KeyCapRow(glyphs: shortcut.modifierSymbols + [shortcut.key.uppercased()])

        let inner = NSStackView(views: [caption, keys])
        inner.orientation = .vertical
        inner.alignment = .centerX
        inner.spacing = 10
        inner.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16)
        inner.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            inner.topAnchor.constraint(equalTo: box.topAnchor),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }
}

/// The shortcut drawn as one dark rounded key cap per glyph.
private final class KeyCapRow: NSStackView {
    private static let side: CGFloat = 34

    convenience init(glyphs: [String]) {
        self.init(frame: .zero)
        orientation = .horizontal
        spacing = 6
        for glyph in glyphs { addArrangedSubview(Self.cap(glyph)) }
    }

    private static func cap(_ glyph: String) -> NSView {
        let label = NSTextField(labelWithString: glyph)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let cap = NSView()
        cap.wantsLayer = true
        cap.layer?.cornerRadius = 8
        cap.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        cap.translatesAutoresizingMaskIntoConstraints = false
        cap.addSubview(label)
        NSLayoutConstraint.activate([
            cap.heightAnchor.constraint(equalToConstant: side),
            cap.widthAnchor.constraint(greaterThanOrEqualToConstant: side),
            label.centerXAnchor.constraint(equalTo: cap.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: cap.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: cap.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cap.trailingAnchor, constant: -8),
        ])
        return cap
    }
}

/// A thin accent-colored capsule that empties from right to left.
private final class ProgressBar: NSView {
    private static let height: CGFloat = 4
    private let fill = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.cornerRadius = Self.height / 2
        fill.backgroundColor = NSColor.controlAccentColor.cgColor
        layer?.addSublayer(fill)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.bounds = CGRect(origin: .zero, size: bounds.size)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
    }

    /// Animates from full to empty over `duration`.
    func run(duration: TimeInterval) {
        let shrink = CABasicAnimation(keyPath: "transform.scale.x")
        shrink.fromValue = 1
        shrink.toValue = 0
        shrink.duration = max(0.01, duration)
        shrink.timingFunction = CAMediaTimingFunction(name: .linear)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.transform = CATransform3DMakeScale(0, 1, 1)
        CATransaction.commit()
        fill.add(shrink, forKey: "progress")
    }
}
