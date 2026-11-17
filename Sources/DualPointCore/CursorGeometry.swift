import Foundation
import CoreGraphics

/// Coordinate math for macOS's global display space.
///
/// CoreGraphics uses a top-left origin with y increasing downward, and the main
/// display's origin is (0, 0). Displays can be arranged in any direction, so
/// built-in displays often have negative coordinates. Every point DualPoint
/// stores or warps to is in this global coordinate space, in *points* (not
/// pixels), which is scale independent.
public enum CursorGeometry {
    /// The display whose bounds contain `point`, if any.
    public static func display(containing point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        // Prefer a strict interior match so shared edges resolve predictably.
        if let strict = displays.first(where: { $0.bounds.insetBy(dx: 0.5, dy: 0.5).contains(point) }) {
            return strict
        }
        return displays.first(where: { $0.bounds.contains(point) })
    }

    /// The display nearest to `point`, used when the point is in a gap between displays.
    public static func nearestDisplay(to point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.min { lhs, rhs in
            squaredDistance(from: point, to: lhs.bounds) < squaredDistance(from: point, to: rhs.bounds)
        }
    }

    public static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// Captures a point as a normalized anchor on the display that contains it.
    public static func anchor(for point: CGPoint, in displays: [DisplayInfo]) -> CursorAnchor? {
        guard let display = display(containing: point, in: displays) ?? nearestDisplay(to: point, in: displays),
              display.bounds.width > 0, display.bounds.height > 0 else {
            return nil
        }
        let x = ((point.x - display.bounds.minX) / display.bounds.width).clamped(to: 0...1)
        let y = ((point.y - display.bounds.minY) / display.bounds.height).clamped(to: 0...1)
        return CursorAnchor(displayUUID: display.id, displayName: display.name, x: x, y: y)
    }

    /// Resolves an anchor back to a global point, if its display is still connected.
    public static func point(for anchor: CursorAnchor, in displays: [DisplayInfo], inset: CGFloat = 2) -> CGPoint? {
        guard let display = displays.first(where: { $0.id == anchor.displayUUID }) else { return nil }
        let raw = CGPoint(
            x: display.bounds.minX + CGFloat(anchor.x) * display.bounds.width,
            y: display.bounds.minY + CGFloat(anchor.y) * display.bounds.height
        )
        return clamped(raw, to: display, inset: inset)
    }

    /// Point to use the first time a device is used, based on its assignment.
    public static func defaultPoint(for display: DisplayInfo, inset: CGFloat = 2) -> CGPoint {
        clamped(CGPoint(x: display.bounds.midX, y: display.bounds.midY), to: display, inset: inset)
    }

    /// Keeps a point on a display, safely away from the outer edge.
    public static func clamped(_ point: CGPoint, to display: DisplayInfo, inset: CGFloat = 2) -> CGPoint {
        let rect = display.bounds
        guard rect.width > 0, rect.height > 0 else { return CGPoint(x: rect.minX, y: rect.minY) }
        let safeInset = min(max(inset, 0), rect.width / 2 - 0.5, rect.height / 2 - 0.5)
        let x = point.x.clamped(to: (rect.minX + safeInset)...(rect.maxX - safeInset))
        let y = point.y.clamped(to: (rect.minY + safeInset)...(rect.maxY - safeInset))
        return CGPoint(x: x, y: y)
    }

    public static func isPointOnAnyDisplay(_ point: CGPoint, displays: [DisplayInfo], tolerance: CGFloat = 1) -> Bool {
        displays.contains { display in
            display.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }

    /// Moves a point by a pointer delta and keeps it on real display content.
    ///
    /// Crossing into an adjacent display is allowed, exactly like the real
    /// cursor. When the movement would leave the display into a gap or past the
    /// outer edge, the point stops at that display's edge instead of floating in
    /// invalid space.
    public static func movedPoint(
        from point: CGPoint,
        by delta: CGSize,
        in displays: [DisplayInfo],
        inset: CGFloat = 2
    ) -> CGPoint {
        let candidate = CGPoint(x: point.x + delta.width, y: point.y + delta.height)
        if isPointOnAnyDisplay(candidate, displays: displays) {
            return candidate
        }
        guard let current = display(containing: point, in: displays) ?? nearestDisplay(to: point, in: displays) else {
            return point
        }
        return clamped(candidate, to: current, inset: inset)
    }

    /// Resolves the point to restore when a device becomes active.
    ///
    /// The device's actual last position wins, even if it was left on another
    /// display. The display assignment is a fallback used for first use, after
    /// a reset, or when the remembered display has been disconnected.
    public static func restorePoint(settings: DeviceSettings, displays: [DisplayInfo], inset: CGFloat = 2) -> CGPoint? {
        if let anchor = settings.anchor,
           let point = point(for: anchor, in: displays, inset: inset) {
            return point
        }
        if let uuid = settings.assignment.displayUUID,
           let display = displays.first(where: { $0.id == uuid }) {
            return defaultPoint(for: display, inset: inset)
        }
        return nil
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension CGPoint {
    public func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
