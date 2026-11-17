import Foundation
import CoreGraphics

/// Where the artificial second cursor currently is.
///
/// The interim cursor is drawn by the app, not by the window server. It only
/// exists while two pointing devices move at the same time.
public struct InterimCursor: Equatable {
    public let deviceID: String
    public let deviceName: String
    /// Global CoreGraphics point (top-left origin), like every other cursor
    /// coordinate in DualPoint.
    public let point: CGPoint

    public init(deviceID: String, deviceName: String, point: CGPoint) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.point = point
    }
}

/// Tuning for the interim cursor and the handover that ends it.
public struct InterimCursorPolicy: Equatable {
    /// The whole feature can be switched off without giving up automatic
    /// switching between devices.
    public var isEnabled: Bool
    /// Minimum quiet time after the interim device stops before the real cursor
    /// moves to it. Also the minimum interval between two automatic handovers,
    /// which prevents the real cursor from ping-ponging when both devices are
    /// used in quick succession.
    public var handoverCooldown: TimeInterval
    /// How recently the main device must have moved for a second moving device
    /// to count as simultaneous instead of a normal handover.
    public var overlapWindow: TimeInterval
    /// How long the interim device must stay still before its position is
    /// adopted by the real cursor.
    public var settleDelay: TimeInterval

    public init(
        isEnabled: Bool = true,
        handoverCooldown: TimeInterval = 0.8,
        overlapWindow: TimeInterval = 0.35,
        settleDelay: TimeInterval = 0.28
    ) {
        self.isEnabled = isEnabled
        self.handoverCooldown = max(0, handoverCooldown)
        self.overlapWindow = max(0.05, overlapWindow)
        self.settleDelay = max(0.05, settleDelay)
    }
}

/// Decides which device owns the real cursor and when a second device gets an
/// interim cursor.
///
/// The rules are intentionally small and testable:
///
/// * The device that moved first keeps the real cursor.
/// * A different device that moves while the first one is still moving gets the
///   interim cursor. It is suppressed by the event tap, so it no longer steers
///   the real cursor.
/// * When the interim device settles and the cooldown has passed, its position
///   is adopted: the real cursor warps to it and it becomes the main device.
/// * A single moving device is never affected.
public struct InterimCursorArbiter: Equatable {
    public private(set) var mainDeviceID: String?
    public private(set) var interimDeviceID: String?
    public private(set) var lastHandoverAt: UInt64?
    public var policy: InterimCursorPolicy

    private var lastMovementAt: [String: UInt64] = [:]

    public init(policy: InterimCursorPolicy = InterimCursorPolicy()) {
        self.policy = policy
    }

    /// Updates the device that owns the real cursor. Called after a normal
    /// handover, a manual activation, or when the active device disappears.
    public mutating func setMain(_ deviceID: String?) {
        mainDeviceID = deviceID
        if let interimDeviceID, interimDeviceID == deviceID {
            self.interimDeviceID = nil
        }
    }

    public mutating func noteMovement(_ deviceID: String, at timestamp: UInt64) {
        if let previous = lastMovementAt[deviceID], previous > timestamp {
            return
        }
        lastMovementAt[deviceID] = timestamp
    }

    public func lastMovement(for deviceID: String) -> UInt64? {
        lastMovementAt[deviceID]
    }

    public func isRecentlyMoving(_ deviceID: String, at now: UInt64) -> Bool {
        guard let last = lastMovementAt[deviceID], now >= last else { return false }
        return now - last <= Self.nanoseconds(policy.overlapWindow)
    }

    public func mainIsRecentlyMoving(at now: UInt64) -> Bool {
        guard let mainDeviceID else { return false }
        return isRecentlyMoving(mainDeviceID, at: now)
    }

    /// True when movement from `deviceID` should become an interim cursor
    /// instead of a normal switch.
    public func canStartInterim(for deviceID: String, at now: UInt64) -> Bool {
        guard policy.isEnabled,
              let mainDeviceID,
              mainDeviceID != deviceID,
              interimDeviceID == nil,
              isRecentlyMoving(mainDeviceID, at: now) else {
            return false
        }
        return true
    }

    public mutating func startInterim(_ deviceID: String) {
        interimDeviceID = deviceID
    }

    public func interimHasSettled(at now: UInt64) -> Bool {
        guard let interimDeviceID else { return false }
        guard let last = lastMovementAt[interimDeviceID] else { return true }
        guard now >= last else { return false }
        return now - last >= Self.nanoseconds(policy.settleDelay)
    }

    public func cooldownElapsed(at now: UInt64) -> Bool {
        guard let lastHandoverAt else { return true }
        guard now >= lastHandoverAt else { return false }
        return now - lastHandoverAt >= Self.nanoseconds(policy.handoverCooldown)
    }

    public func canAdoptInterim(at now: UInt64) -> Bool {
        guard let interimDeviceID, cooldownElapsed(at: now) else { return false }

        // The user-facing handover delay is the quiet time the interim device
        // has to produce after its last movement. Never undercut the internal
        // settle delay, which absorbs a momentary pause mid-gesture.
        let requiredQuiet = Self.nanoseconds(
            max(policy.settleDelay, policy.handoverCooldown)
        )
        guard let last = lastMovementAt[interimDeviceID] else { return true }
        guard now >= last else { return false }
        return now - last >= requiredQuiet
    }

    /// Makes the interim device the main device and starts the cooldown.
    /// Returns the device that now owns the real cursor.
    @discardableResult
    public mutating func adoptInterim(at now: UInt64) -> String? {
        guard let deviceID = interimDeviceID else { return nil }
        interimDeviceID = nil
        mainDeviceID = deviceID
        lastHandoverAt = now
        return deviceID
    }

    public mutating func cancelInterim() {
        interimDeviceID = nil
    }

    public mutating func reset() {
        mainDeviceID = nil
        interimDeviceID = nil
        lastMovementAt.removeAll()
        lastHandoverAt = nil
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        // The policy clamps negative values; the extra guard keeps this safe if
        // a caller constructs a policy in another way.
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
