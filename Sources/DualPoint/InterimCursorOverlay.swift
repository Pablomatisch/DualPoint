import AppKit
import QuartzCore
import DualPointCore

/// Draws the app-owned second cursor.
///
/// The overlay is one transparent, non-activating window that spans every
/// display. It never accepts mouse events and never becomes key, so it cannot
/// interfere with the app underneath. The arrow is a Core Animation shape, which
/// makes fast movement cheap: the engine can update it at event rate without
/// invalidating any SwiftUI view.
@MainActor
final class InterimCursorOverlay {
    /// The electric blue from the app icon. The interim cursor has to read as
    /// part of DualPoint, not as another system cursor.
    private static let cursorColor = NSColor(
        srgbRed: 0.36,
        green: 0.55,
        blue: 1.0,
        alpha: 1.0
    )

    private let window: OverlayWindow
    private let cursorLayer = CAShapeLayer()
    private let contentView: FlippedView
    private var screenObserver: NSObjectProtocol?
    private var currentPoint: CGPoint?
    /// Global CoreGraphics union of every screen, top-left origin.
    private var screenUnion: CGRect = .zero

    private static let arrowSize = CGSize(width: 22, height: 30)
    /// Empty room around the arrow inside its layer bounds for the stroke and
    /// glow. The hotspot is the arrow tip at this inset.
    private static let arrowInset: CGFloat = 10

    init() {
        contentView = FlippedView(frame: .zero)
        window = OverlayWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.contentView = contentView

        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = false
        configureCursorLayer()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreenGeometry()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - Visibility

    func show(_ cursor: InterimCursor) {
        let wasVisible = window.isVisible
        currentPoint = cursor.point

        if !wasVisible {
            refreshScreenGeometry()
            cursorLayer.removeAllAnimations()
            cursorLayer.opacity = 1
            window.alphaValue = 0
            window.orderFrontRegardless()
        }

        moveLayer(to: cursor.point, animated: false)

        // Movement can restart while the fade-out is still running. A new
        // animation to 1 wins over it; setting alpha directly could be
        // overwritten by the running animator and leave the ghost invisible.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = wasVisible ? 0.10 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard window.isVisible else { return }
        currentPoint = nil
        cursorLayer.removeAllAnimations()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.currentPoint == nil else { return }
                self.window.orderOut(nil)
                self.window.alphaValue = 1
            }
        }
    }

    /// Keeps the overlay current if a display connects while a ghost is up.
    /// The engine normally hides the ghost on a configuration change; this is
    /// only a safety net.
    func refreshScreenGeometry() {
        let geometry = Self.currentScreenGeometry()
        screenUnion = geometry.union
        guard window.frame != geometry.windowFrame else { return }
        window.setFrame(geometry.windowFrame, display: false)
        if let point = currentPoint {
            moveLayer(to: point, animated: false)
        }
    }

    // MARK: - Rendering

    private func configureCursorLayer() {
        let path = Self.arrowPath()

        cursorLayer.path = path
        cursorLayer.fillColor = Self.cursorColor.cgColor
        cursorLayer.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        cursorLayer.lineWidth = 1.3
        cursorLayer.lineJoin = .round
        cursorLayer.lineCap = .round
        cursorLayer.fillRule = .nonZero
        cursorLayer.masksToBounds = false

        cursorLayer.shadowColor = Self.cursorColor.cgColor
        cursorLayer.shadowOpacity = 0.85
        cursorLayer.shadowRadius = 7
        cursorLayer.shadowOffset = .zero

        cursorLayer.anchorPoint = .zero
        cursorLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: Self.arrowSize.width + Self.arrowInset * 2,
            height: Self.arrowSize.height + Self.arrowInset * 2
        )
        contentView.layer?.addSublayer(cursorLayer)
    }

    private func moveLayer(to point: CGPoint, animated: Bool) {
        let local = CGPoint(
            x: point.x - screenUnion.minX,
            y: point.y - screenUnion.minY
        )
        let target = CGPoint(
            x: local.x - Self.arrowInset,
            y: local.y - Self.arrowInset
        )

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.10)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            cursorLayer.position = target
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.position = target
            CATransaction.commit()
        }
    }

    /// A crisp, classic arrow. It is drawn with the hotspot at the layer inset
    /// so the shape never sits on a half pixel at 1× or 2×.
    private static func arrowPath() -> CGPath {
        let p = arrowInset
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p, y: p))
        path.addLine(to: CGPoint(x: p, y: p + 21))
        path.addLine(to: CGPoint(x: p + 5.0, y: p + 16.6))
        path.addLine(to: CGPoint(x: p + 8.4, y: p + 23.8))
        path.addLine(to: CGPoint(x: p + 12.1, y: p + 22.1))
        path.addLine(to: CGPoint(x: p + 8.7, y: p + 15.0))
        path.addLine(to: CGPoint(x: p + 14.8, y: p + 15.0))
        path.closeSubpath()
        return path
    }

    // MARK: - Geometry

    private struct ScreenGeometry {
        let union: CGRect
        let windowFrame: CGRect
    }

    private static func currentScreenGeometry() -> ScreenGeometry {
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero })
            ?? screens.first else {
            return ScreenGeometry(union: .zero, windowFrame: .zero)
        }
        let primaryHeight = primary.frame.height

        var union: CGRect?
        for screen in screens {
            let cgRect = CGRect(
                x: screen.frame.minX,
                y: primaryHeight - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            union = union.map { $0.union(cgRect) } ?? cgRect
        }
        let cgUnion = union ?? .zero
        // Cocoa's window coordinates are bottom-left based on the primary
        // screen; the union keeps the same size, only its origin flips.
        let windowFrame = CGRect(
            x: cgUnion.minX,
            y: primaryHeight - cgUnion.maxY,
            width: cgUnion.width,
            height: cgUnion.height
        )
        return ScreenGeometry(union: cgUnion, windowFrame: windowFrame)
    }
}

// MARK: - Window plumbing

/// A flipped, transparent view so local overlay coordinates match the
/// top-left Core Graphics coordinates the engine already uses for cursors.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}
