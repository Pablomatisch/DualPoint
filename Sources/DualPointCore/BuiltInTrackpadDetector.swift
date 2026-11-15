import Foundation
import IOKit.hid
import CoreGraphics

/// Detects the built-in trackpad, which macOS exposes as a DriverKit
/// `IOHIDEventService` rather than a classic IOHIDDevice on Apple Silicon.
///
/// The public IOHIDEventSystemClient service list is enough to identify it.
/// Its actual pointer activity arrives through the system event tap and is
/// attributed to this device by the engine.
public enum BuiltInTrackpadDetector {
    public struct ServiceSummary: Equatable {
        public let product: String
        public let isBuiltIn: Bool
        public let usagePage: Int
        public let usage: Int
        public let transport: String
    }

    public static func hasBuiltInTrackpad() -> Bool {
        services().contains { service in
            let name = service.product.lowercased()
            return service.isBuiltIn && (name.contains("trackpad") || (service.usagePage == 0x0D && service.usage == 0x05))
        }
    }

    public static func services() -> [ServiceSummary] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let rawServices = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }

        var result: [ServiceSummary] = []
        for service in rawServices {
            let product = stringProperty(service, "Product")
            guard !product.isEmpty else { continue }
            let builtIn = (property(service, "Built-In") as? NSNumber)?.boolValue ?? false
            let usagePage = (property(service, "PrimaryUsagePage") as? NSNumber)?.intValue ?? 0
            let usage = (property(service, "PrimaryUsage") as? NSNumber)?.intValue ?? 0
            let transport = stringProperty(service, "Transport")
            result.append(ServiceSummary(
                product: product,
                isBuiltIn: builtIn,
                usagePage: usagePage,
                usage: usage,
                transport: transport
            ))
        }
        return result
    }

    /// Names of services that look like pointing hardware, for diagnostics.
    public static func pointingServiceNames() -> [String] {
        services().filter { service in
            service.usagePage == 0x01 && (service.usage == 0x01 || service.usage == 0x02)
                || service.usagePage == 0x0D && service.usage == 0x05
                || service.product.lowercased().contains("trackpad")
                || service.product.lowercased().contains("mouse")
        }.map { "\($0.product)\($0.isBuiltIn ? " (built-in)" : "")" }
    }

    private static func property(_ service: IOHIDServiceClient, _ key: String) -> Any? {
        IOHIDServiceClientCopyProperty(service, key as CFString)
    }

    private static func stringProperty(_ service: IOHIDServiceClient, _ key: String) -> String {
        (property(service, key) as? String) ?? ""
    }
}
