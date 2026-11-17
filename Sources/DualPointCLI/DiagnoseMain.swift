import Foundation
import CoreGraphics
@preconcurrency import DualPointCore

/// Diagnostic command line tool used to verify device identification,
/// attribution and display geometry on real hardware.
///
/// Usage:
///   DualPointDiagnose list      devices, displays and permissions
///   DualPointDiagnose watch     live device/display changes
///   DualPointDiagnose monitor   live HID reports and attributed pointer events
///   DualPointDiagnose dual       seize the first external device and verify raw X/Y signs
@main
struct DualPointDiagnose {
    @MainActor
    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)

        let arguments = Array(CommandLine.arguments.dropFirst())
        let mode = arguments.first ?? "list"
        let runner = Runner()

        switch mode {
        case "list":
            runner.list()
        case "watch":
            runner.watch()
        case "monitor":
            runner.monitor()
        case "dual":
            runner.dual()
        case "help", "--help", "-h":
            print("""
            DualPointDiagnose — hardware diagnostics for DualPoint

              list      connected devices, displays and permissions
              watch     stream device and display changes
              monitor   stream HID activity and attributed pointer events
              dual      seize the first external device and verify raw X/Y signs
                        (quit DualPoint first so the device can be seized)
            """)
        default:
            FileHandle.standardError.write(Data("Unknown command: \(mode)\n".utf8))
            exit(2)
        }
    }
}

@MainActor
final class Runner {
    private let hid = HIDMonitor()
    private let tap = EventTapMonitor()
    private var devices: [String: HIDDeviceInfo] = [:]
    private var activity = ActivityTable()
    private var lastEventDescription: String?

    func list() {
        print("DualPoint diagnostics")
        print("=====================")

        printDisplays()
        print("")
        print("Built-in trackpad: \(BuiltInTrackpadDetector.hasBuiltInTrackpad() ? "detected" : "not found")")
        print("Pointing services: \(BuiltInTrackpadDetector.pointingServiceNames().joined(separator: ", "))")

        print("")
        print("Enumerating HID devices…")
        hid.onDeviceAdded = { [weak self] info in
            guard let self else { return }
            self.devices[info.key] = info
            self.printDevice(info)
        }
        hid.onDeviceRemoved = { [weak self] id in
            self?.devices.removeValue(forKey: id)
            print("  removed \(id)")
        }
        hid.onError = { message in
            print("  HID error: \(message)")
        }
        hid.start()

        tap.onStateChange = { state in
            print("Event tap: \(state)")
        }
        _ = tap.start()

        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        let hidWasOpen = hid.isOpen
        let lastOpenResult = hid.lastOpenResult
        let tapWasAvailable = tap.state.isRunning
        tap.stop()
        hid.stop()

        print("")
        let permissions = PermissionCenter.snapshot(eventTapAvailable: tapWasAvailable)
        print("Permissions")
        print("  Input Monitoring (HID): \(permissions.hidAccessGranted)")
        print("  Input Monitoring (events): \(permissions.listenEventAccessGranted)")
        print("  Accessibility: \(permissions.accessibilityTrusted)")
        print("  Event tap available: \(tapWasAvailable)")
        print("  HID manager open: \(hidWasOpen) (last result \(String(format: "0x%08x", lastOpenResult)))")
        print("")
    }

    func watch() {
        print("Watching device and display changes. Press Control-C to stop.")
        printDisplays()

        hid.onDeviceAdded = { [weak self] info in
            print("+ \(info.name) [\(info.key)] \(info.vendorID.map { String(format: "%04X", $0) } ?? "?")")
            self?.devices[info.key] = info
        }
        hid.onDeviceRemoved = { [weak self] id in
            print("- \(self?.devices[id]?.name ?? id) [\(id)]")
            self?.devices.removeValue(forKey: id)
        }
        hid.onActivity = { [weak self] activity in
            guard let self else { return }
            self.activity.record(
                deviceID: activity.deviceID,
                timestamp: activity.timestamp,
                isMovement: activity.isMovement
            )
            print("  \(self.devices[activity.deviceID]?.name ?? activity.deviceID): \(activity.detail)")
        }
        hid.onError = { print("  HID error: \($0)") }
        hid.start()

        tap.onPointerEvent = { [weak self] event in
            self?.printEvent(event)
            return .pass
        }
        tap.start()

        RunLoop.main.run()
    }

    func monitor() {
        print("Monitoring. Move each device. Press Control-C to stop.")
        printDisplays()

        hid.onDeviceAdded = { [weak self] info in
            self?.devices[info.key] = info
            print("+ \(info.name) [\(info.key)]")
        }
        hid.onDeviceRemoved = { [weak self] id in
            print("- \(self?.devices[id]?.name ?? id)")
            self?.devices.removeValue(forKey: id)
            self?.activity.remove(deviceID: id)
        }
        hid.onActivity = { [weak self] activity in
            guard let self else { return }
            self.activity.record(
                deviceID: activity.deviceID,
                timestamp: activity.timestamp,
                isMovement: activity.isMovement
            )
            let name = self.devices[activity.deviceID]?.name ?? activity.deviceID
            print("HID    \(self.time(activity.timestamp))  \(name)  \(activity.detail)")
        }
        hid.onError = { print("  HID error: \($0)") }
        hid.start()

        tap.onStateChange = { print("Event tap: \($0)") }
        tap.onPointerEvent = { [weak self] event in
            self?.printEvent(event)
            return .pass
        }
        tap.start()

        RunLoop.main.run()
    }

    /// Verifies the exact raw-HID path the interim cursor uses. Seizing the
    /// device stops it from moving the real pointer, so the printed deltas are
    /// the same numbers the blue cursor consumes.
    func dual() {
        print("Dual-pointer raw HID verification. Quit DualPoint first. Press Control-C to stop.")
        print("Move ONLY the external mouse. Up must print negative dy, down positive dy.")
        printDisplays()

        var candidate: HIDDeviceInfo?
        var seizureAttempted = false

        hid.onDeviceAdded = { [weak self] info in
            self?.devices[info.key] = info
            print("+ \(info.name) [\(info.key)] uniqueID=\(info.uniqueID) builtIn=\(info.isBuiltIn)")
            if candidate == nil, !info.isBuiltIn, info.uniqueID != 0 {
                candidate = info
            }
        }
        hid.onDeviceRemoved = { [weak self] id in
            print("- \(self?.devices[id]?.name ?? id) [\(id)]")
            self?.devices.removeValue(forKey: id)
            self?.activity.remove(deviceID: id)
        }
        hid.onError = { print("  HID error: \($0)") }
        hid.onOwnershipChange = { uniqueID, seized in
            print("HID ownership uniqueID=\(uniqueID) \(seized ? "seized (exclusive)" : "released")")
        }
        hid.onSeizedMovement = { movement in
            // Same gain curve as the engine's scaledRawDelta.
            let dx = movement.delta.x
            let dy = movement.delta.y
            let gain = 1 + min(hypot(dx, dy), 40) / 40
            print(String(
                format: "RAW   dx=%6.0f dy=%6.0f gain=%.2f  → CG dx=%7.1f dy=%7.1f",
                dx, dy, gain, dx * gain, dy * gain
            ))
        }
        hid.onSeizedButton = { button in
            print("BUTTON usage=\(button.usage) \(button.isPressed ? "down" : "up")")
        }
        hid.onSeizedScroll = { scroll in
            print("SCROLL dx=\(scroll.delta.x) dy=\(scroll.delta.y)")
        }
        hid.start()

        tap.onStateChange = { print("Event tap: \($0)") }
        tap.onPointerEvent = { [weak self] event in
            self?.printEvent(event)
            return .pass
        }
        tap.start()

        _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard !seizureAttempted, let candidate else { return }
                seizureAttempted = true
                let ok = self.hid.seize(deviceUniqueID: candidate.uniqueID)
                print("Seizing \(candidate.name) (uniqueID=\(candidate.uniqueID)): \(ok ? "ok" : "FAILED")")
            }
        }

        RunLoop.main.run()
    }

    private func printEvent(_ event: PointerEvent) {
        guard event.isMeaningfulActivity else { return }
        let match = activity.device(forEventAt: event.timestamp)
        let owner: String
        if let match {
            owner = devices[match.deviceID]?.name ?? match.deviceID
        } else {
            owner = "built-in trackpad (unattributed)"
        }

        let latency: String
        if let match, event.timestamp >= match.timestamp {
            latency = String(format: " +%.1fms", Double(event.timestamp - match.timestamp) / 1_000_000)
        } else {
            latency = ""
        }

        let description = "\(event.type.rawValue) \(event.debugSummary)"
        guard description != lastEventDescription else { return }
        lastEventDescription = description

        print("EVENT  \(time(event.timestamp))  \(owner)\(latency)  \(event.debugSummary)  at \(event.location)")
    }

    private func time(_ timestamp: UInt64) -> String {
        String(format: "%10.3f", Double(timestamp) / 1_000_000_000)
    }

    private func printDisplays() {
        print("")
        print("Displays")
        for display in DisplayManager.enumerate() {
            let flags = [display.isMain ? "main" : nil, display.isBuiltIn ? "built-in" : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
            print("  \(display.name)  \(display.bounds)  \(display.resolutionLabel) @\(display.scale)x  \(flags)")
            print("    \(display.id)")
        }
    }

    private func printDevice(_ info: HIDDeviceInfo) {
        let identity = info.identityDescription
        print("  \(info.name)  [\(info.key)]")
        print("    kind=\(info.kind.rawValue) builtIn=\(info.isBuiltIn) uniqueID=\(info.uniqueID) \(identity)")
    }
}

private extension HIDDeviceInfo {
    var identityDescription: String {
        var parts: [String] = []
        if let vendorID, let productID {
            parts.append(String(format: "%04X:%04X", vendorID, productID))
        }
        if let serialNumber { parts.append("S/N \(serialNumber)") }
        if let locationID { parts.append(String(format: "loc %08X", locationID)) }
        if let transport { parts.append(transport) }
        return parts.joined(separator: " ")
    }
}
