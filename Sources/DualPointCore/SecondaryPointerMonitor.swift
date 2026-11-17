import Foundation
import CoreGraphics
import IOKit
import IOKit.hid

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

/// Gives the interim cursor exclusive, raw-HID ownership of one external device.
///
/// This is the same mechanism DoubleMouse uses. Seizing stops the device from
/// steering the real macOS pointer at the source, so the blue pointer cannot
/// drag the real one along behind it with an offset. Raw counts are reported
/// here and translated into screen points by the engine.
///
/// The built-in trackpad is a DriverKit event service and cannot be seized this
/// way. The engine keeps the event-tap path as a fallback for it.
@MainActor
public final class SecondaryPointerMonitor {
    public var onMovement: ((SecondaryPointerDelta) -> Void)?
    public var onScroll: ((SecondaryPointerScroll) -> Void)?
    public var onButton: ((SecondaryPointerButton) -> Void)?
    public var onError: ((String) -> Void)?

    public private(set) var isOpen = false
    public private(set) var seizedDeviceUniqueID: UInt64?

    public var canSeizeDevices: Bool { isOpen }

    private var manager: IOHIDManager?
    private var devices: [UInt64: IOHIDDevice] = [:]
    private var started = false
    private var pendingDelta = CGPoint.zero
    private var pendingDeviceUniqueID: UInt64?
    private var flushScheduled = false

    public init() {}

    deinit {
        // stop() is called by the engine; this is only a safety net.
    }

    public func start() {
        guard !started else { return }
        started = true

        // Public SDK value for kIOHIDManagerOptionIndependentDevices. It lets
        // this manager open a device that the attribution manager already has
        // open passively.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0x8))
        self.manager = manager

        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchPad],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = result == kIOReturnSuccess
        if !isOpen {
            onError?("Secondary device manager failed to open (0x\(String(format: "%08x", result))).")
        }
    }

    public func stop() {
        guard started else { return }
        started = false

        release()
        for device in devices.values {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        devices.removeAll()

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        isOpen = false
        resetPending()
    }

    /// Takes exclusive ownership of one device. Returns false when the system
    /// refuses the seize; the caller can then fall back to event-tap suppression.
    @discardableResult
    public func seize(deviceUniqueID: UInt64) -> Bool {
        guard isOpen, let device = devices[deviceUniqueID] else { return false }
        if seizedDeviceUniqueID == deviceUniqueID { return true }

        release()
        resetPending()
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result == kIOReturnSuccess {
            seizedDeviceUniqueID = deviceUniqueID
            return true
        }

        // Leave the device usable for normal input and attribution.
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        onError?("Could not seize the second device (0x\(String(format: "%08x", result))).")
        return false
    }

    /// Returns a seized device to the window server.
    public func release() {
        guard let seizedDeviceUniqueID, let device = devices[seizedDeviceUniqueID] else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.seizedDeviceUniqueID = nil
        resetPending()
    }

    // MARK: - Device lifecycle

    fileprivate func deviceAdded(_ device: IOHIDDevice) {
        let id = Self.uniqueID(for: device)
        guard devices[id] == nil else { return }
        devices[id] = device

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(device, inputValueCallback, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        let id = Self.uniqueID(for: device)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        devices.removeValue(forKey: id)
        if seizedDeviceUniqueID == id {
            seizedDeviceUniqueID = nil
            resetPending()
        }
    }

    // MARK: - Input

    fileprivate func inputValue(_ value: IOHIDValue) {
        guard let seizedDeviceUniqueID else { return }
        let element = IOHIDValueGetElement(value)
        guard Self.uniqueID(for: IOHIDElementGetDevice(element)) == seizedDeviceUniqueID else { return }

        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)

        switch (page, usage) {
        case (Int(kHIDPage_GenericDesktop), Int(kHIDUsage_GD_X)):
            accumulate(CGPoint(x: CGFloat(intValue), y: 0), deviceUniqueID: seizedDeviceUniqueID)
        case (Int(kHIDPage_GenericDesktop), Int(kHIDUsage_GD_Y)):
            accumulate(CGPoint(x: 0, y: CGFloat(intValue)), deviceUniqueID: seizedDeviceUniqueID)
        case (Int(kHIDPage_GenericDesktop), Int(kHIDUsage_GD_Wheel)):
            flushPendingMovement()
            onScroll?(SecondaryPointerScroll(
                deviceUniqueID: seizedDeviceUniqueID,
                delta: CGPoint(x: 0, y: CGFloat(intValue))
            ))
        case (Int(kHIDPage_Consumer), 0x238): // Horizontal wheel / tilt.
            flushPendingMovement()
            onScroll?(SecondaryPointerScroll(
                deviceUniqueID: seizedDeviceUniqueID,
                delta: CGPoint(x: CGFloat(intValue), y: 0)
            ))
        case (Int(kHIDPage_Button), 1), (Int(kHIDPage_Button), 2), (Int(kHIDPage_Button), 3):
            flushPendingMovement()
            onButton?(SecondaryPointerButton(
                deviceUniqueID: seizedDeviceUniqueID,
                usage: usage,
                isPressed: intValue != 0
            ))
        default:
            break
        }
    }

    /// HID reports arrive one element at a time. Coalesce X and Y from the same
    /// report so the blue pointer moves diagonally in one step, not two.
    private func accumulate(_ delta: CGPoint, deviceUniqueID: UInt64) {
        if pendingDeviceUniqueID != nil, pendingDeviceUniqueID != deviceUniqueID {
            flushPendingMovement()
        }
        pendingDeviceUniqueID = deviceUniqueID
        pendingDelta.x += delta.x
        pendingDelta.y += delta.y
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingMovement()
        }
    }

    private func flushPendingMovement() {
        flushScheduled = false
        let delta = pendingDelta
        let id = pendingDeviceUniqueID
        resetPending()
        guard let id, delta.x != 0 || delta.y != 0 else { return }
        onMovement?(SecondaryPointerDelta(deviceUniqueID: id, delta: delta))
    }

    private func resetPending() {
        pendingDelta = .zero
        pendingDeviceUniqueID = nil
    }

    private static func uniqueID(for device: IOHIDDevice) -> UInt64 {
        if let number = IOHIDDeviceGetProperty(device, "UniqueID" as CFString) as? NSNumber,
           number.uint64Value != 0 {
            return number.uint64Value
        }
        let service = IOHIDDeviceGetService(device)
        var entryID: UInt64 = 0
        if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS, entryID != 0 {
            return entryID
        }
        return UInt64(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
    }
}

// MARK: - C callbacks

private let deviceAddedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let monitor = Unmanaged<SecondaryPointerMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.deviceAdded(device) }
}

private let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let monitor = Unmanaged<SecondaryPointerMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.deviceRemoved(device) }
}

private let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    let monitor = Unmanaged<SecondaryPointerMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.inputValue(value) }
}
