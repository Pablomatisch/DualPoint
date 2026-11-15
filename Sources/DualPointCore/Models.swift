import Foundation
import CoreGraphics

// MARK: - Devices

/// The physical class of a pointing device as far as DualPoint is concerned.
public enum DeviceKind: String, Codable, CaseIterable {
    case builtInTrackpad
    case mouse
    case trackpad
    case other

    public var label: String {
        switch self {
        case .builtInTrackpad: return "Built-in Trackpad"
        case .mouse: return "Mouse"
        case .trackpad: return "Trackpad"
        case .other: return "Pointing Device"
        }
    }
}

/// A connected physical pointing device, merged with the user's preferences.
public struct PointingDevice: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var kind: DeviceKind
    public var isBuiltIn: Bool
    public var vendorID: Int?
    public var productID: Int?
    public var locationID: Int?
    public var serialNumber: String?
    public var transport: String?
    public var isConnected: Bool
    public var isEnabled: Bool
    public var assignment: DisplayAssignment
    public var isActive: Bool
    public var hasSavedPosition: Bool

    public init(
        id: String,
        name: String,
        kind: DeviceKind,
        isBuiltIn: Bool = false,
        vendorID: Int? = nil,
        productID: Int? = nil,
        locationID: Int? = nil,
        serialNumber: String? = nil,
        transport: String? = nil,
        isConnected: Bool = true,
        isEnabled: Bool = true,
        assignment: DisplayAssignment = .unmanaged,
        isActive: Bool = false,
        hasSavedPosition: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isBuiltIn = isBuiltIn
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.serialNumber = serialNumber
        self.transport = transport
        self.isConnected = isConnected
        self.isEnabled = isEnabled
        self.assignment = assignment
        self.isActive = isActive
        self.hasSavedPosition = hasSavedPosition
    }

    /// Whether DualPoint is allowed to restore this device's cursor position.
    public var isManaged: Bool {
        isConnected && isEnabled && !assignment.isUnmanaged
    }

    public var connectionLabel: String {
        guard isConnected else { return "Disconnected" }
        if isBuiltIn { return "Built-in" }
        if let transport, !transport.isEmpty {
            return transport.uppercased() == "BLUETOOTH" ? "Bluetooth" : transport.uppercased()
        }
        return "Connected"
    }

    public var identityDescription: String {
        var parts: [String] = []
        if let vendorID, let productID {
            parts.append(String(format: "%04X:%04X", vendorID, productID))
        }
        if let serialNumber, !serialNumber.isEmpty {
            parts.append("S/N \(serialNumber)")
        }
        if let locationID, locationID != 0 {
            parts.append(String(format: "loc %08X", locationID))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Displays

public struct DisplayInfo: Identifiable, Equatable {
    public let id: String
    public let displayID: CGDirectDisplayID
    public let name: String
    public let bounds: CGRect
    public let isBuiltIn: Bool
    public let isMain: Bool
    public let pointWidth: Int
    public let pointHeight: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let scale: Double

    public init(
        id: String,
        displayID: CGDirectDisplayID,
        name: String,
        bounds: CGRect,
        isBuiltIn: Bool,
        isMain: Bool,
        pointWidth: Int,
        pointHeight: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: Double
    ) {
        self.id = id
        self.displayID = displayID
        self.name = name
        self.bounds = bounds
        self.isBuiltIn = isBuiltIn
        self.isMain = isMain
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
    }

    public var resolutionLabel: String {
        "\(pointWidth) × \(pointHeight)"
    }

    public var detailLabel: String {
        var parts = [resolutionLabel]
        if scale > 1 { parts.append("@\(Int(scale))×") }
        if isBuiltIn { parts.append("Built-in") }
        if isMain { parts.append("Main") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Assignment & persistence

public struct DisplayAssignment: Codable, Hashable {
    /// `nil` means Unmanaged.
    public var displayUUID: String?
    /// Remembered display name so the UI can explain a disconnected assignment.
    public var displayName: String?

    public init(displayUUID: String?, displayName: String? = nil) {
        self.displayUUID = displayUUID
        self.displayName = displayName
    }

    public static let unmanaged = DisplayAssignment(displayUUID: nil)

    public var isUnmanaged: Bool { displayUUID == nil }
}

/// A resolution-independent cursor position on a specific display.
public struct CursorAnchor: Codable, Equatable {
    public var displayUUID: String
    public var displayName: String?
    /// Position within the display, 0...1 from the display's top-left corner.
    public var x: Double
    public var y: Double

    public init(displayUUID: String, displayName: String? = nil, x: Double, y: Double) {
        self.displayUUID = displayUUID
        self.displayName = displayName
        self.x = x
        self.y = y
    }
}

public struct DeviceSettings: Codable, Equatable {
    public var assignment: DisplayAssignment
    public var isEnabled: Bool
    public var anchor: CursorAnchor?
    /// Cached hardware metadata so a disconnected device can still be listed
    /// with a recognizable name instead of its opaque identity key.
    public var lastKnownName: String?
    public var lastKnownKind: DeviceKind?

    public init(
        assignment: DisplayAssignment = .unmanaged,
        isEnabled: Bool = true,
        anchor: CursorAnchor? = nil,
        lastKnownName: String? = nil,
        lastKnownKind: DeviceKind? = nil
    ) {
        self.assignment = assignment
        self.isEnabled = isEnabled
        self.anchor = anchor
        self.lastKnownName = lastKnownName
        self.lastKnownKind = lastKnownKind
    }
}

public struct PersistedState: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var automaticSwitching: Bool
    public var onboardingCompleted: Bool
    public var devices: [String: DeviceSettings]

    public init(
        schemaVersion: Int = PersistedState.currentSchemaVersion,
        automaticSwitching: Bool = true,
        onboardingCompleted: Bool = false,
        devices: [String: DeviceSettings] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.automaticSwitching = automaticSwitching
        self.onboardingCompleted = onboardingCompleted
        self.devices = devices
    }

    public func settings(for deviceID: String) -> DeviceSettings {
        devices[deviceID] ?? DeviceSettings()
    }

    public mutating func update(deviceID: String, _ body: (inout DeviceSettings) -> Void) {
        var settings = devices[deviceID] ?? DeviceSettings()
        body(&settings)
        devices[deviceID] = settings
    }
}

// MARK: - Identity

public enum DeviceIdentity {
    public static let builtInTrackpadID = "builtin.trackpad"

    /// Builds a stable, human-readable key from HID properties.
    ///
    /// Prefers a hardware serial number, then the USB location, and only then
    /// the product name. Registry entry IDs are deliberately not used because
    /// they change when a device is reconnected.
    public static func stableKey(
        vendorID: Int?,
        productID: Int?,
        locationID: Int?,
        serialNumber: String?,
        name: String,
        isBuiltIn: Bool
    ) -> String {
        if isBuiltIn && name.lowercased().contains("trackpad") {
            return builtInTrackpadID
        }

        let vid = vendorID ?? 0
        let pid = productID ?? 0
        let base = String(format: "hid:%04x:%04x", vid, pid)

        if let serial = serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !serial.isEmpty {
            return "\(base):sn:\(sanitize(serial))"
        }
        if let location = locationID, location != 0 {
            return "\(base):loc:\(String(location, radix: 16))"
        }
        return "\(base):name:\(sanitize(name))"
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars).lowercased()
    }
}

// MARK: - Runtime status

public struct SwitchRecord: Equatable {
    public let deviceID: String
    public let deviceName: String
    public let fromDeviceID: String?
    public let at: Date
    public let restoredPoint: CGPoint?
    public let wasWarped: Bool

    public init(
        deviceID: String,
        deviceName: String,
        fromDeviceID: String?,
        at: Date = Date(),
        restoredPoint: CGPoint?,
        wasWarped: Bool
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.fromDeviceID = fromDeviceID
        self.at = at
        self.restoredPoint = restoredPoint
        self.wasWarped = wasWarped
    }
}

public struct PermissionSnapshot: Equatable {
    public var hidAccessGranted: Bool
    public var listenEventAccessGranted: Bool
    public var eventTapAvailable: Bool
    public var accessibilityTrusted: Bool

    public init(
        hidAccessGranted: Bool = false,
        listenEventAccessGranted: Bool = false,
        eventTapAvailable: Bool = false,
        accessibilityTrusted: Bool = false
    ) {
        self.hidAccessGranted = hidAccessGranted
        self.listenEventAccessGranted = listenEventAccessGranted
        self.eventTapAvailable = eventTapAvailable
        self.accessibilityTrusted = accessibilityTrusted
    }

    public var isReadyForAutomaticSwitching: Bool {
        hidAccessGranted && eventTapAvailable
    }

    public var needsInputMonitoring: Bool {
        !hidAccessGranted || !listenEventAccessGranted
    }
}
