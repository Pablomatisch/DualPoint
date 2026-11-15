import Foundation

/// Correlates system-wide pointer events with the physical HID device that
/// produced them.
///
/// macOS does not annotate `CGEvent`s with a device identity. DualPoint
/// therefore records the timestamp of every report received from a known HID
/// device and attributes a CGEvent to the most recent report that immediately
/// precedes it. The CGEvents produced by the built-in trackpad are not backed
/// by any HID report (it is a DriverKit event service), so they remain
/// unattributed and are mapped to the built-in trackpad by the engine.
public struct ActivityTable {
    public struct Entry: Equatable {
        public let deviceID: String
        public let timestamp: UInt64
        public let isMovement: Bool
    }

    /// Reports older than this are never attributed to a CGEvent. Observed
    /// report→event latency on the test machine is 1–8 ms.
    public var attributionWindow: UInt64
    /// Clock skew tolerance when a report timestamp is slightly after the event.
    public var futureTolerance: UInt64

    private var entries: [String: Entry] = [:]

    public init(
        attributionWindow: UInt64 = 25_000_000,
        futureTolerance: UInt64 = 2_000_000
    ) {
        self.attributionWindow = attributionWindow
        self.futureTolerance = futureTolerance
    }

    public mutating func record(deviceID: String, timestamp: UInt64, isMovement: Bool) {
        if let existing = entries[deviceID], existing.timestamp > timestamp {
            // Callbacks are normally ordered; never let a late, older report
            // replace a newer timestamp.
            return
        }
        entries[deviceID] = Entry(deviceID: deviceID, timestamp: timestamp, isMovement: isMovement)
    }

    /// Returns the device whose report best explains an event at `timestamp`.
    public func device(forEventAt timestamp: UInt64) -> Entry? {
        var best: Entry?
        for entry in entries.values {
            let delta: UInt64
            if timestamp >= entry.timestamp {
                delta = timestamp - entry.timestamp
            } else if entry.timestamp - timestamp <= futureTolerance {
                delta = 0
            } else {
                continue
            }
            guard delta <= attributionWindow else { continue }
            if best == nil || entry.timestamp > best!.timestamp {
                best = entry
            }
        }
        return best
    }

    public mutating func remove(deviceID: String) {
        entries.removeValue(forKey: deviceID)
    }

    public mutating func clear() {
        entries.removeAll()
    }

    public var trackedDeviceIDs: [String] {
        Array(entries.keys)
    }
}

/// Mach absolute time helpers.
///
/// `CGEvent.timestamp` and `IOHIDValueGetTimeStamp` both return mach absolute
/// time ticks (verified on Apple Silicon), so both are converted to nanoseconds
/// before attribution. `DispatchTime.uptimeNanoseconds` is already in that unit.
public enum Clock {
    public static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    public static func ticksToNanoseconds(_ ticks: UInt64) -> UInt64 {
        ticks &* timebase.numer / timebase.denom
    }

    public static func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
