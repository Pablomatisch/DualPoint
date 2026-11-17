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

    /// Delivers a click from the interim device at the blue pointer. Used only
    /// after the device has been released and the real cursor handed over.
    public static func click(at point: CGPoint, button: CGMouseButton, isPressed: Bool) {
        guard let source = syntheticSource else { return }
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
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        )
        event?.post(tap: .cghidEventTap)
    }

    /// Scrolls the window under the blue pointer without moving the real one.
    public static func scroll(at point: CGPoint, horizontal: Int64, vertical: Int64) {
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
    }
}
