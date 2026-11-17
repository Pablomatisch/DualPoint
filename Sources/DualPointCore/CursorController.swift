import Foundation
import CoreGraphics
import AppKit

/// The only place DualPoint moves the real system cursor.
///
/// `CGWarpMouseCursorPosition` does not require Accessibility permission and,
/// for on-screen coordinates, does not generate pointer events. DualPoint never
/// displays a second cursor and never confines the pointer to a display.
@MainActor
public enum CursorController {
    public static func currentPosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    public static func currentDisplay(in displays: [DisplayInfo]) -> DisplayInfo? {
        CursorGeometry.display(containing: currentPosition(), in: displays)
    }

    public static func isAnyButtonDown() -> Bool {
        for button in [CGMouseButton.left, .right, .center] {
            if CGEventSource.buttonState(.combinedSessionState, button: button) {
                return true
            }
        }
        for buttonNumber in 3...31 {
            guard let button = CGMouseButton(rawValue: UInt32(buttonNumber)) else { continue }
            if CGEventSource.buttonState(.combinedSessionState, button: button) {
                return true
            }
        }
        return false
    }

    @discardableResult
    public static func warp(to point: CGPoint) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        let result = CGWarpMouseCursorPosition(point)
        return result == .success
    }

    /// Warps to a display center, used for first-time placement and resets.
    @discardableResult
    public static func warpToCenter(of display: DisplayInfo) -> Bool {
        warp(to: CursorGeometry.defaultPoint(for: display))
    }

    // MARK: - Synthetic input for a seized device

    private static let syntheticSource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()

    /// Delivers one click half at the blue pointer. A CG mouse event carries
    /// its own location, so the window server moves the real cursor there
    /// briefly. Pass the main device's position as `returnPoint` to put it back
    /// immediately, as DoubleMouse does.
    public static func click(
        at point: CGPoint,
        button: CGMouseButton,
        isPressed: Bool,
        returningTo returnPoint: CGPoint? = nil
    ) {
        let type: CGEventType
        switch (button, isPressed) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        case (.center, true): type = .otherMouseDown
        case (.center, false): type = .otherMouseUp
        default: type = isPressed ? .leftMouseDown : .leftMouseUp
        }
        postMouseEvent(type, button: button, at: point, returningTo: returnPoint)
    }

    /// Synthesizes a left drag from the blue pointer while the real cursor is
    /// restored to the main device after every event.
    public static func beginDrag(at point: CGPoint, returningTo returnPoint: CGPoint) {
        postMouseEvent(.leftMouseDown, button: .left, at: point, returningTo: returnPoint)
    }

    public static func drag(to point: CGPoint, returningTo returnPoint: CGPoint) {
        postMouseEvent(.leftMouseDragged, button: .left, at: point, returningTo: returnPoint)
    }

    public static func endDrag(at point: CGPoint, returningTo returnPoint: CGPoint) {
        postMouseEvent(.leftMouseUp, button: .left, at: point, returningTo: returnPoint)
    }

    /// Scrolls the window under the blue pointer and restores the real cursor.
    public static func scroll(
        at point: CGPoint,
        horizontal: Int64,
        vertical: Int64,
        returningTo returnPoint: CGPoint? = nil
    ) {
        guard let source = syntheticSource else { return }
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: vertical),
            wheel2: Int32(clamping: horizontal),
            wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
        if let returnPoint { _ = warp(to: returnPoint) }
    }

    private static func postMouseEvent(
        _ type: CGEventType,
        button: CGMouseButton,
        at point: CGPoint,
        returningTo returnPoint: CGPoint?
    ) {
        guard let source = syntheticSource else { return }
        CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
        if let returnPoint { _ = warp(to: returnPoint) }
    }
}
