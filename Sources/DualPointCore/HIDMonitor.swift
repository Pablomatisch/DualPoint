import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

public struct HIDDeviceInfo: Equatable, Sendable {
    public let key: String
    public let name: String
    public let kind: DeviceKind
    public let isBuiltIn: Bool
    public let vendorID: Int?
    public let productID: Int?
    public let locationID: Int?
    public let serialNumber: String?
    public let transport: String?
    public let uniqueID: UInt64
}

public struct HIDActivity {
    public let deviceID: String
    public let timestamp: UInt64
    public let isMovement: Bool
    /// A button press starts a new interaction and is allowed to switch even
    /// while another device is dragging.
    public let isButtonPress: Bool
    public let detail: String
}

/// Watches every connected pointing device through one IOHIDManager.
///
/// This mirrors DoubleMouse: one manager, one open handle per device. A device
/// that drives the blue pointer is closed and reopened with
/// `kIOHIDOptionsTypeSeizeDevice` on that same handle, which is what actually
/// stops the window server from moving the real cursor. Keeping a second,
/// passive manager open on the same device prevents that and makes both
/// pointers follow the mouse, so there is deliberately no second HID manager.
///
/// The built-in trackpad on Apple Silicon Macs is exposed as a DriverKit
/// `IOHIDEventService`, not as a classic IOHIDDevice, so its reports never
/// reach this monitor. It is detected separately (see BuiltInTrackpadDetector)
/// and its activity is inferred from system pointer events. It can never be
/// seized and therefore can never own the blue pointer.
@MainActor
public final class HIDMonitor {
    public var onDeviceAdded: ((HIDDeviceInfo) -> Void)?
    public var onDeviceRemoved: ((String) -> Void)?
    public var onActivity: ((HIDActivity) -> Void)?
    public var onError: ((String) -> Void)?
    public var onBuiltInTrackpadSeen: (() -> Void)?
    public var onOwnershipChange: ((UInt64, Bool) -> Void)?

    /// Raw reports from the currently seized device. These drive the blue cursor.
    public var onSeizedMovement: ((SecondaryPointerDelta) -> Void)?
    public var onSeizedScroll: ((SecondaryPointerScroll) -> Void)?
    public var onSeizedButton: ((SecondaryPointerButton) -> Void)?

    public private(set) var isOpen = false
    public private(set) var lastOpenResult: IOReturn = kIOReturnSuccess
    public private(set) var seizedDeviceUniqueID: UInt64?
    public var canSeizeDevices: Bool { isOpen }
    public var deviceCount: Int { records.count }

    private var manager: IOHIDManager?
    private var records: [UInt64: Record] = [:]
    private var keyToUniqueID: [String: UInt64] = [:]
    private var started = false

    // X/Y arrive as separate values in one HID report. Coalesce them so the
    // blue pointer moves diagonally in one step.
    private var pendingSecondaryDelta = CGPoint.zero
    private var pendingSecondaryDeviceUniqueID: UInt64?
    private var secondaryFlushScheduled = false

    fileprivate final class ActivityContext {
        unowned let monitor: HIDMonitor
        let deviceID: String
        init(monitor: HIDMonitor, deviceID: String) {
            self.monitor = monitor
            self.deviceID = deviceID
        }
    }

    private struct Record {
        let info: HIDDeviceInfo
        let device: IOHIDDevice
        let context: ActivityContext
        var reportBuffer: UnsafeMutablePointer<UInt8>?
        var lastValueAt: UInt64
        var isOpen: Bool
    }

    public init() {}

    deinit {
        // Manager/records are torn down by stop(); deinit is a safety net.
    }

    public func start() {
        guard !started else { return }
        started = true

        // Public SDK value for kIOHIDManagerOptionIndependentDevices. Devices
        // stay available even while one of them is opened exclusively.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(0x8))
        self.manager = manager

        let matching: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer, kIOHIDDeviceUsageKey: kHIDUsage_Dig_TouchPad],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceAddedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, hidValueManagerCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        lastOpenResult = result
        isOpen = (result == kIOReturnSuccess)
        if !isOpen {
            onError?("IOHIDManagerOpen failed (\(hex(result))). Input Monitoring may be denied.")
        }
    }

    public func stop() {
        guard started else { return }
        started = false

        releaseSeized()
        for (_, record) in records {
            IOHIDDeviceUnscheduleFromRunLoop(record.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(record.device, IOOptionBits(kIOHIDOptionsTypeNone))
            if let buffer = record.reportBuffer {
                buffer.deallocate()
            }
        }
        records.removeAll()
        keyToUniqueID.removeAll()

        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        isOpen = false
        resetPendingSecondary()
    }

    /// Re-enumerates after a permission change.
    public func restart() {
        let wasStarted = started
        stop()
        if wasStarted { start() }
    }

    // MARK: - Exclusive ownership

    /// Gives the blue pointer exclusive ownership of one external device.
    /// Returns false when the system refuses the seize; the caller then keeps
    /// the normal single cursor. This is the same close/reopen sequence
    /// DoubleMouse uses.
    @discardableResult
    public func seize(deviceUniqueID: UInt64) -> Bool {
        guard isOpen, let record = records[deviceUniqueID], record.isOpen else { return false }
        if seizedDeviceUniqueID == deviceUniqueID { return true }
        if seizedDeviceUniqueID != nil { releaseSeized() }

        let device = record.device
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result == kIOReturnSuccess {
            seizedDeviceUniqueID = deviceUniqueID
            resetPendingSecondary()
            onOwnershipChange?(deviceUniqueID, true)
            return true
        }

        // Leave the device usable for normal input and attribution.
        IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        onError?("Could not seize the second device (0x\(String(format: "%08x", result))).")
        return false
    }

    /// Returns the seized device to the window server.
    public func releaseSeized() {
        guard let uniqueID = seizedDeviceUniqueID, let record = records[uniqueID] else { return }
        IOHIDDeviceClose(record.device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceOpen(record.device, IOOptionBits(kIOHIDOptionsTypeNone))
        seizedDeviceUniqueID = nil
        resetPendingSecondary()
        onOwnershipChange?(uniqueID, false)
    }

    // MARK: - Device lifecycle

    fileprivate func handleDeviceAdded(_ device: IOHIDDevice) {
        let uid = uniqueID(for: device)
        guard records[uid] == nil else { return }

        let name = stringProperty(device, kIOHIDProductKey).nilIfEmpty ?? "Unknown Pointing Device"
        let vendorID = intProperty(device, kIOHIDVendorIDKey)
        let productID = intProperty(device, kIOHIDProductIDKey)
        let locationID = intProperty(device, kIOHIDLocationIDKey)
        let transport = stringProperty(device, kIOHIDTransportKey)
        let isBuiltIn = boolProperty(device, kIOHIDBuiltInKey)
        let serial = stringProperty(device, kIOHIDSerialNumberKey).nilIfEmpty
            ?? physicalUniqueID(device)

        let pairs = property(device, kIOHIDDeviceUsagePairsKey) as? [[String: Any]] ?? []
        let hasDigitizer = pairs.contains { pair in
            (pair[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue == Int(kHIDPage_Digitizer)
                && (pair[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue == Int(kHIDUsage_Dig_TouchPad)
        }
        let looksLikeTrackpad = hasDigitizer || name.lowercased().contains("trackpad")

        let kind: DeviceKind
        if isBuiltIn && looksLikeTrackpad {
            kind = .builtInTrackpad
        } else if looksLikeTrackpad {
            kind = .trackpad
        } else {
            kind = .mouse
        }

        if kind == .builtInTrackpad {
            onBuiltInTrackpadSeen?()
            return
        }

        let baseKey = DeviceIdentity.stableKey(
            vendorID: vendorID,
            productID: productID,
            locationID: locationID,
            serialNumber: serial,
            name: name,
            isBuiltIn: isBuiltIn
        )
        // If two identical devices are connected at once, distinguish them by
        // their (transient) registry ID so both can be used simultaneously.
        let key: String
        if keyToUniqueID[baseKey] != nil {
            key = "\(baseKey)#\(uid)"
        } else {
            key = baseKey
        }

        let info = HIDDeviceInfo(
            key: key,
            name: name,
            kind: kind,
            isBuiltIn: isBuiltIn,
            vendorID: vendorID,
            productID: productID,
            locationID: locationID,
            serialNumber: serial,
            transport: transport,
            uniqueID: uid
        )

        // DoubleMouse schedules each device on the main run loop before opening
        // it. Without this, per-device value callbacks never fire: attribution
        // fails, the external mouse is inferred as the built-in trackpad, and
        // no blue pointer is ever created.
        let context = ActivityContext(monitor: self, deviceID: key)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        let capacity = max(64, intProperty(device, kIOHIDMaxInputReportSizeKey) ?? 4096)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)

        IOHIDDeviceRegisterInputValueCallback(device, hidValueDeviceCallback, contextPointer)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            hidReportCallback,
            contextPointer
        )

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        let record = Record(
            info: info,
            device: device,
            context: context,
            reportBuffer: buffer,
            lastValueAt: 0,
            isOpen: result == kIOReturnSuccess
        )

        if !record.isOpen {
            onError?("Could not open \(name) (\(hex(result))). It will be listed but cannot be attributed.")
        }

        records[uid] = record
        keyToUniqueID[key] = uid
        onDeviceAdded?(info)
    }

    fileprivate func handleDeviceRemoved(_ device: IOHIDDevice) {
        let uid = uniqueID(for: device)
        guard let record = records.removeValue(forKey: uid) else { return }
        keyToUniqueID.removeValue(forKey: record.info.key)

        if seizedDeviceUniqueID == uid {
            seizedDeviceUniqueID = nil
            resetPendingSecondary()
            onOwnershipChange?(uid, false)
        }
        IOHIDDeviceUnscheduleFromRunLoop(record.device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(record.device, IOOptionBits(kIOHIDOptionsTypeNone))
        if let buffer = record.reportBuffer {
            buffer.deallocate()
        }
        onDeviceRemoved?(record.info.key)
    }

    // MARK: - Input

    fileprivate func handle(value: IOHIDValue, for deviceID: String) {
        let element = IOHIDValueGetElement(value)
        let elementUniqueID = uniqueID(for: IOHIDElementGetDevice(element))

        if elementUniqueID == seizedDeviceUniqueID {
            handleSeizedValue(value, element: element, uniqueID: elementUniqueID)
            return
        }
        guard keyToUniqueID[deviceID] != nil else { return }

        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)

        var isMovement = false
        var isButtonPress = false
        var meaningful = false
        var detail = ""

        switch page {
        case Int(kHIDPage_GenericDesktop):
            switch usage {
            case 0x30, 0x31: // X, Y
                isMovement = intValue != 0
                meaningful = isMovement
                detail = "\(usage == 0x30 ? "X" : "Y") \(intValue)"
            case 0x38: // wheel
                isMovement = intValue != 0
                meaningful = isMovement
                detail = "wheel \(intValue)"
            default:
                meaningful = false
            }
        case Int(kHIDPage_Button):
            // A press starts a new interaction; a release alone is not a
            // reason to yank the cursor to another display.
            meaningful = intValue != 0
            isButtonPress = intValue != 0
            detail = "button \(usage) \(intValue != 0 ? "down" : "up")"
        case Int(kHIDPage_Consumer):
            meaningful = intValue != 0
            detail = "consumer \(usage) \(intValue)"
        default:
            meaningful = false
        }

        guard meaningful else { return }

        let rawTimestamp = IOHIDValueGetTimeStamp(value)
        let timestamp = rawTimestamp == 0 ? Clock.nowNanoseconds() : Clock.ticksToNanoseconds(rawTimestamp)

        if let uid = keyToUniqueID[deviceID], var record = records[uid] {
            record.lastValueAt = Clock.nowNanoseconds()
            records[uid] = record
        }

        onActivity?(HIDActivity(
            deviceID: deviceID,
            timestamp: timestamp,
            isMovement: isMovement,
            isButtonPress: isButtonPress,
            detail: detail
        ))
    }

    fileprivate func handleReport(deviceID: String, length: Int) {
        guard let uid = keyToUniqueID[deviceID], let record = records[uid] else { return }
        if uid == seizedDeviceUniqueID { return }
        // Devices that deliver input values are already handled precisely.
        // Some trackpads only deliver raw reports; treat an isolated report as
        // activity so they can still trigger a device switch.
        // Once a device has delivered structured values, ignore its raw
        // reports: they are the same physical report and would duplicate.
        guard record.lastValueAt == 0 else { return }
        let now = Clock.nowNanoseconds()
        onActivity?(HIDActivity(
            deviceID: deviceID,
            timestamp: now,
            isMovement: true,
            isButtonPress: false,
            detail: "input report (\(length) bytes)"
        ))
    }

    // MARK: - Seized device input

    private func handleSeizedValue(_ value: IOHIDValue, element: IOHIDElement, uniqueID: UInt64) {
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)

        switch (page, usage) {
        case (Int(kHIDPage_GenericDesktop), Int(kHIDUsage_GD_X)):
            accumulateSecondary(CGPoint(x: CGFloat(intValue), y: 0), uniqueID: uniqueID)
        case (Int(kHIDPage_GenericDesktop), Int(kHIDUsage_GD_Y)):
            accumulateSecondary(CGPoint(x: 0, y: CGFloat(intValue)), uniqueID: uniqueID)
        case (Int(kHIDPage_GenericDesktop), Int(kHIDUsage_GD_Wheel)):
            flushSecondaryMovement()
            onSeizedScroll?(SecondaryPointerScroll(
                deviceUniqueID: uniqueID,
                delta: CGPoint(x: 0, y: CGFloat(intValue))
            ))
        case (Int(kHIDPage_Consumer), 0x238): // Horizontal wheel / tilt.
            flushSecondaryMovement()
            onSeizedScroll?(SecondaryPointerScroll(
                deviceUniqueID: uniqueID,
                delta: CGPoint(x: CGFloat(intValue), y: 0)
            ))
        case (Int(kHIDPage_Button), 1), (Int(kHIDPage_Button), 2), (Int(kHIDPage_Button), 3):
            flushSecondaryMovement()
            onSeizedButton?(SecondaryPointerButton(
                deviceUniqueID: uniqueID,
                usage: usage,
                isPressed: intValue != 0
            ))
        default:
            break
        }
    }

    private func accumulateSecondary(_ delta: CGPoint, uniqueID: UInt64) {
        if let pending = pendingSecondaryDeviceUniqueID, pending != uniqueID {
            flushSecondaryMovement()
        }
        pendingSecondaryDeviceUniqueID = uniqueID
        pendingSecondaryDelta.x += delta.x
        pendingSecondaryDelta.y += delta.y
        guard !secondaryFlushScheduled else { return }
        secondaryFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushSecondaryMovement()
        }
    }

    private func flushSecondaryMovement() {
        secondaryFlushScheduled = false
        let delta = pendingSecondaryDelta
        let uniqueID = pendingSecondaryDeviceUniqueID
        resetPendingSecondary()
        guard let uniqueID, delta.x != 0 || delta.y != 0 else { return }
        onSeizedMovement?(SecondaryPointerDelta(deviceUniqueID: uniqueID, delta: delta))
    }

    private func resetPendingSecondary() {
        pendingSecondaryDelta = .zero
        pendingSecondaryDeviceUniqueID = nil
        secondaryFlushScheduled = false
    }

    // MARK: - Properties

    private func uniqueID(for device: IOHIDDevice) -> UInt64 {
        if let number = property(device, "UniqueID") as? NSNumber, number.uint64Value != 0 {
            return number.uint64Value
        }
        let service = IOHIDDeviceGetService(device)
        var entryID: UInt64 = 0
        if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS, entryID != 0 {
            return entryID
        }
        return UInt64(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private func stringProperty(_ device: IOHIDDevice, _ key: String) -> String {
        (property(device, key) as? String) ?? ""
    }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (property(device, key) as? NSNumber)?.intValue
    }

    private func boolProperty(_ device: IOHIDDevice, _ key: String) -> Bool {
        (property(device, key) as? NSNumber)?.boolValue ?? false
    }

    private func physicalUniqueID(_ device: IOHIDDevice) -> String? {
        if let value = property(device, "PhysicalDeviceUniqueID") as? String {
            return value
        }
        if let data = property(device, "PhysicalDeviceUniqueID") as? Data {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }
}

private func hex(_ value: IOReturn) -> String {
    String(format: "0x%08x", value)
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - C callbacks

private let hidDeviceAddedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handleDeviceAdded(device)
    }
}

private let hidDeviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handleDeviceRemoved(device)
    }
}

private let hidValueManagerCallback: IOHIDValueCallback = { _, _, _, _ in
    // Per-device callbacks do the work; the manager-level callback is unused.
}

private let hidValueDeviceCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else { return }
    let activity = Unmanaged<HIDMonitor.ActivityContext>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        activity.monitor.handle(value: value, for: activity.deviceID)
    }
}

private let hidReportCallback: IOHIDReportCallback = { context, _, _, _, _, _, length in
    guard let context else { return }
    let activity = Unmanaged<HIDMonitor.ActivityContext>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        activity.monitor.handleReport(deviceID: activity.deviceID, length: length)
    }
}
