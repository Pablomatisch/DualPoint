import AppKit
import DualPointCore

/// Draws the app-owned second pointer.
///
/// The arrow is the system arrow image, tinted with DualPoint's electric blue.
/// Using `NSCursor.arrow.image` and its hotspot keeps it exactly the same size
/// as the real cursor; the overlay is transparent, non-activating and ignores
/// mouse events so it cannot disturb the app underneath.
@MainActor
final class InterimCursorOverlay {
    private static let cursorColor = NSColor(
        srgbRed: 0.36,
        green: 0.55,
        blue: 1.0,
        alpha: 1.0
    )

    private let window: OverlayWindow
    private let pointerView = PointerView(frame: .zero)
    private var screenObserver: NSObjectProtocol?
    private var currentPoint: CGPoint?
    /// Global Core Graphics union of every screen, top-left origin.
    private var screenUnion: CGRect = .zero

    init() {
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
        window.contentView = pointerView

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshScreenGeometry()
            }
        }
        refreshScreenGeometry()
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: - Visibility

    func show(_ cursor: InterimCursor) {
        currentPoint = cursor.point
        if !window.isVisible {
            refreshScreenGeometry()
            window.orderFrontRegardless()
        }
        moveView(to: cursor.point)
    }

    /// Hiding is immediate. A delayed fade could leave a second pointer on
    /// screen after the real cursor has already taken over.
    func hide() {
        currentPoint = nil
        window.orderOut(nil)
    }

    /// Keeps the overlay correct if a display connects while a pointer is up.
    /// The engine normally hides it on a configuration change; this is a safety net.
    func refreshScreenGeometry() {
        let geometry = Self.currentScreenGeometry()
        screenUnion = geometry.union
        if window.frame != geometry.windowFrame {
            window.setFrame(geometry.windowFrame, display: false)
        }
        let contentRect = window.contentRect(forFrameRect: window.frame)
        pointerView.frame = NSRect(origin: .zero, size: contentRect.size)
        if let point = currentPoint {
            moveView(to: point)
        }
    }

    // MARK: - Geometry

    private func moveView(to point: CGPoint) {
        // The content view is flipped, so local coordinates use the same
        // top-left origin as Core Graphics.
        pointerView.pointerPosition = CGPoint(
            x: point.x - screenUnion.minX,
            y: point.y - screenUnion.minY
        )
    }

    private struct ScreenGeometry {
        let union: CGRect
        let windowFrame: CGRect
    }

    private static func currentScreenGeometry() -> ScreenGeometry {
        let screens = NSScreen.screens
        guard let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first else {
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
        let windowFrame = CGRect(
            x: cgUnion.minX,
            y: primaryHeight - cgUnion.maxY,
            width: cgUnion.width,
            height: cgUnion.height
        )
        return ScreenGeometry(union: cgUnion, windowFrame: windowFrame)
    }
}

// MARK: - Pointer drawing

/// Draws the tinted system arrow at its natural size.
private final class PointerView: NSView {
    private let image = PointerView.tintedArrow()
    private let hotSpot = NSCursor.arrow.hotSpot

    var pointerPosition: CGPoint = .zero {
        didSet {
            setNeedsDisplay(dirtyRect(around: oldValue))
            setNeedsDisplay(dirtyRect(around: pointerPosition))
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = image.size
        let rect = NSRect(
            x: pointerPosition.x - hotSpot.x,
            y: pointerPosition.y - hotSpot.y,
            width: size.width,
            height: size.height
        )
        image.draw(in: rect)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func dirtyRect(around point: CGPoint) -> NSRect {
        let size = image.size
        return NSRect(
            x: point.x - hotSpot.x - 2,
            y: point.y - hotSpot.y - 2,
            width: size.width + 4,
            height: size.height + 4
        )
    }

    private static func tintedArrow() -> NSImage {
        let arrow = NSCursor.arrow.image
        let image = NSImage(size: arrow.size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: arrow.size)
        arrow.draw(in: rect)
        cursorColor.withAlphaComponent(0.9).setFill()
        rect.fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }

    private static var cursorColor: NSColor {
        NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1.0)
    }
}

// MARK: - Window plumbing

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}
