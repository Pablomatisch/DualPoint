import Foundation
import CoreGraphics

/// Raw movement from the device currently driving the app-owned second pointer.
public struct SecondaryPointerDelta {
    public let deviceUniqueID: UInt64
    /// Raw HID counts. X is positive right, Y is positive away from the user.
    public let delta: CGPoint

    public init(deviceUniqueID: UInt64, delta: CGPoint) {
        self.deviceUniqueID = deviceUniqueID
        self.delta = delta
    }
}

public struct SecondaryPointerScroll {
    public let deviceUniqueID: UInt64
    public let delta: CGPoint

    public init(deviceUniqueID: UInt64, delta: CGPoint) {
        self.deviceUniqueID = deviceUniqueID
        self.delta = delta
    }
}

public struct SecondaryPointerButton {
    public let deviceUniqueID: UInt64
    /// HID button usage: 1 = left, 2 = right, 3 = middle.
    public let usage: Int
    public let isPressed: Bool

    public init(deviceUniqueID: UInt64, usage: Int, isPressed: Bool) {
        self.deviceUniqueID = deviceUniqueID
        self.usage = usage
        self.isPressed = isPressed
    }
}
