import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the menu bar UI can show the real system
/// status rather than a cached preference.
public enum LoginItemManager {
    public enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case notFound
        case unknown(String)

        public var label: String {
            switch self {
            case .enabled: return "Enabled"
            case .disabled: return "Off"
            case .requiresApproval: return "Waiting for approval"
            case .notFound: return "Move DualPoint to Applications"
            case .unknown(let detail): return detail
            }
        }

        public var isOn: Bool { self == .enabled }
    }

    public static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unknown("Unknown")
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
