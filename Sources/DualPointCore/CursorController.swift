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
}
