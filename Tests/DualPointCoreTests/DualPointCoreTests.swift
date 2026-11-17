import Foundation
import CoreGraphics
import DualPointCore

/// A dependency-free test runner.
///
/// The Command Line Tools installation does not ship XCTest, so DualPoint's
/// unit tests run as a small executable instead:
///
///     swift run DualPointSelfTest
@main
struct DualPointSelfTest {
    static func main() {
        let suite = TestSuite()
        DeviceIdentityTests.run(suite)
        CursorGeometryTests.run(suite)
        AttributionTests.run(suite)
        InterimCursorTests.run(suite)
        PersistedStateTests.run(suite)
        PointingDeviceTests.run(suite)

        print("")
        print("\(suite.passed) passed, \(suite.failed) failed")
        exit(suite.failed == 0 ? 0 : 1)
    }
}

final class TestSuite {
    private(set) var passed = 0
    private(set) var failed = 0

    func run(_ name: String, _ body: () -> Void) {
        let failuresBefore = failed
        body()
        if failed == failuresBefore {
            print("  ✓ \(name)")
        } else {
            print("  ✗ \(name)")
        }
    }

    func check(
        _ condition: Bool,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if condition {
            passed += 1
        } else {
            failed += 1
            print("      \(message())  [\(file):\(line)]")
        }
    }

    func equal<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: @autoclosure () -> String = "value",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        check(actual == expected, "\(label()): expected \(expected), got \(actual)", file: file, line: line)
    }

    func approximate(
        _ actual: Double,
        _ expected: Double,
        tolerance: Double = 0.001,
        _ label: @autoclosure () -> String = "value",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        check(
            abs(actual - expected) <= tolerance,
            "\(label()): expected \(expected) ± \(tolerance), got \(actual)",
            file: file,
            line: line
        )
    }
}

// MARK: - Identity

enum DeviceIdentityTests {
    static func run(_ suite: TestSuite) {
        print("DeviceIdentity")

        suite.run("built-in trackpad has a stable ID") {
            let id = DeviceIdentity.stableKey(
                vendorID: 0x05AC,
                productID: 0x8102,
                locationID: 0,
                serialNumber: nil,
                name: "Apple Internal Keyboard / Trackpad",
                isBuiltIn: true
            )
            suite.equal(id, DeviceIdentity.builtInTrackpadID)
        }

        suite.run("serial number wins over location") {
            let id = DeviceIdentity.stableKey(
                vendorID: 0x046D,
                productID: 0xC077,
                locationID: 0x1130000,
                serialNumber: "ABC 123",
                name: "USB Optical Mouse",
                isBuiltIn: false
            )
            suite.equal(id, "hid:046d:c077:sn:abc_123")
        }

        suite.run("location is stable without a serial number") {
            let first = DeviceIdentity.stableKey(
                vendorID: 0x046D,
                productID: 0xC077,
                locationID: 0x1130000,
                serialNumber: nil,
                name: "USB Optical Mouse",
                isBuiltIn: false
            )
            let second = DeviceIdentity.stableKey(
                vendorID: 0x046D,
                productID: 0xC077,
                locationID: 0x1130000,
                serialNumber: nil,
                name: "Different Product String",
                isBuiltIn: false
            )
            suite.equal(first, second)
            suite.equal(first, "hid:046d:c077:loc:1130000")
        }

        suite.run("name is the last fallback") {
            let id = DeviceIdentity.stableKey(
                vendorID: nil,
                productID: nil,
                locationID: 0,
                serialNumber: nil,
                name: "My Mouse!",
                isBuiltIn: false
            )
            suite.equal(id, "hid:0000:0000:name:my_mouse_")
        }
    }
}

// MARK: - Geometry

enum CursorGeometryTests {
    static let external = DisplayInfo(
        id: "external",
        displayID: 3,
        name: "External",
        bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        isBuiltIn: false,
        isMain: true,
        pointWidth: 2560,
        pointHeight: 1440,
        pixelWidth: 5120,
        pixelHeight: 2880,
        scale: 2
    )

    static let builtIn = DisplayInfo(
        id: "builtin",
        displayID: 1,
        name: "Built-in",
        bounds: CGRect(x: -801, y: 1440, width: 1710, height: 1112),
        isBuiltIn: true,
        isMain: false,
        pointWidth: 1710,
        pointHeight: 1112,
        pixelWidth: 3420,
        pixelHeight: 2224,
        scale: 2
    )

    static let displays = [external, builtIn]

    static func run(_ suite: TestSuite) {
        print("CursorGeometry")

        suite.run("display containing a point") {
            suite.equal(CursorGeometry.display(containing: CGPoint(x: 10, y: 10), in: displays)?.id, "external")
            suite.equal(CursorGeometry.display(containing: CGPoint(x: -100, y: 1600), in: displays)?.id, "builtin")
            suite.check(CursorGeometry.display(containing: CGPoint(x: 3000, y: 3000), in: displays) == nil, "point outside displays")
        }

        suite.run("anchor round trip") {
            let point = CGPoint(x: -100, y: 1600)
            guard let anchor = CursorGeometry.anchor(for: point, in: displays) else {
                suite.check(false, "anchor should exist")
                return
            }
            suite.equal(anchor.displayUUID, "builtin")
            let resolved = CursorGeometry.point(for: anchor, in: displays)
            suite.approximate(Double(resolved?.x ?? 0), Double(point.x))
            suite.approximate(Double(resolved?.y ?? 0), Double(point.y))
        }

        suite.run("anchor is normalized and clamped") {
            let topLeft = CursorGeometry.anchor(for: CGPoint(x: -801, y: 1440), in: displays)
            suite.approximate(topLeft?.x ?? -1, 0, tolerance: 0.0001)
            suite.approximate(topLeft?.y ?? -1, 0, tolerance: 0.0001)

            let bottomRight = CursorGeometry.anchor(for: CGPoint(x: 909, y: 2552), in: displays)
            suite.approximate(bottomRight?.x ?? -1, 1, tolerance: 0.0001)
            suite.approximate(bottomRight?.y ?? -1, 1, tolerance: 0.0001)
        }

        suite.run("clamping keeps the point inside the inset") {
            let clamped = CursorGeometry.clamped(CGPoint(x: 5000, y: -100), to: external, inset: 2)
            suite.check(clamped.x <= external.bounds.maxX - 2, "x clamped")
            suite.check(clamped.y >= external.bounds.minY + 2, "y clamped")
        }

        suite.run("actual last position wins over assignment") {
            let anchor = CursorAnchor(displayUUID: "builtin", displayName: "Built-in", x: 0.5, y: 0.5)
            let settings = DeviceSettings(
                assignment: DisplayAssignment(displayUUID: "external", displayName: "External"),
                anchor: anchor
            )
            let point = CursorGeometry.restorePoint(settings: settings, displays: displays)
            suite.approximate(Double(point?.x ?? 0), -801 + 1710 * 0.5)
            suite.approximate(Double(point?.y ?? 0), 1440 + 1112 * 0.5)
        }

        suite.run("assignment is the fallback when the anchor display is gone") {
            let anchor = CursorAnchor(displayUUID: "disconnected", displayName: "Old Display", x: 0.5, y: 0.5)
            let settings = DeviceSettings(
                assignment: DisplayAssignment(displayUUID: "external", displayName: "External"),
                anchor: anchor
            )
            let point = CursorGeometry.restorePoint(settings: settings, displays: displays)
            suite.approximate(Double(point?.x ?? 0), Double(external.bounds.midX))
            suite.approximate(Double(point?.y ?? 0), Double(external.bounds.midY))
        }

        suite.run("no reachable position returns nil") {
            let anchor = CursorAnchor(displayUUID: "disconnected", displayName: nil, x: 0.5, y: 0.5)
            let settings = DeviceSettings(
                assignment: DisplayAssignment(displayUUID: "also-disconnected"),
                anchor: anchor
            )
            suite.check(CursorGeometry.restorePoint(settings: settings, displays: displays) == nil, "no restore point")
        }

        suite.run("point outside displays is detected") {
            suite.check(!CursorGeometry.isPointOnAnyDisplay(CGPoint(x: 5000, y: 5000), displays: displays), "outside")
            suite.check(CursorGeometry.isPointOnAnyDisplay(CGPoint(x: 300, y: 300), displays: displays), "inside")
        }

        suite.run("interim movement follows the pointer delta") {
            let moved = CursorGeometry.movedPoint(
                from: CGPoint(x: 100, y: 100),
                by: CGSize(width: 25, height: -10),
                in: displays
            )
            suite.approximate(Double(moved.x), 125)
            suite.approximate(Double(moved.y), 90)
        }

        suite.run("interim movement crosses into an adjacent display") {
            // The two displays share the edge at y = 1440.
            let moved = CursorGeometry.movedPoint(
                from: CGPoint(x: 100, y: 1438),
                by: CGSize(width: 0, height: 8),
                in: displays
            )
            suite.approximate(Double(moved.y), 1446)
            suite.equal(CursorGeometry.display(containing: moved, in: displays)?.id, "builtin")
        }

        suite.run("interim movement stops at the outer edge") {
            let moved = CursorGeometry.movedPoint(
                from: CGPoint(x: 2550, y: 700),
                by: CGSize(width: 50, height: 0),
                in: displays
            )
            suite.check(moved.x <= external.bounds.maxX, "stays on the display")
            suite.approximate(Double(moved.x), Double(external.bounds.maxX - 2))
        }
    }
}

// MARK: - Interim cursor

enum InterimCursorTests {
    static let ms: UInt64 = 1_000_000
    static let second: UInt64 = 1_000_000_000

    static func run(_ suite: TestSuite) {
        print("InterimCursor")

        suite.run("a single moving device is never intercepted") {
            var arbiter = InterimCursorArbiter()
            arbiter.setMain("mouse")
            arbiter.noteMovement("mouse", at: second)
            suite.check(
                !arbiter.canStartInterim(for: "mouse", at: second + 10 * ms),
                "the main device keeps the real cursor"
            )
            suite.check(
                arbiter.canStartInterim(for: "trackpad", at: second + 10 * ms),
                "a different device may use the interim cursor"
            )
        }

        suite.run("a second device is only eligible while the main is moving") {
            var arbiter = InterimCursorArbiter(
                policy: InterimCursorPolicy(overlapWindow: 0.2)
            )
            arbiter.setMain("mouse")
            arbiter.noteMovement("mouse", at: second)
            suite.check(
                arbiter.canStartInterim(for: "trackpad", at: second + 150 * ms),
                "inside the overlap window"
            )
            suite.check(
                !arbiter.canStartInterim(for: "trackpad", at: second + 250 * ms),
                "after the overlap window"
            )
        }

        suite.run("the interim device must settle before adoption") {
            var arbiter = InterimCursorArbiter()
            arbiter.setMain("mouse")
            arbiter.noteMovement("mouse", at: second)
            arbiter.noteMovement("trackpad", at: second + 50 * ms)
            arbiter.startInterim("trackpad")

            suite.equal(arbiter.interimDeviceID, "trackpad")
            suite.check(!arbiter.interimHasSettled(at: second + 100 * ms), "still moving")
            suite.check(arbiter.interimHasSettled(at: second + 350 * ms), "settled")
        }

        suite.run("adoption promotes the interim device and starts the cooldown") {
            var arbiter = InterimCursorArbiter(
                policy: InterimCursorPolicy(handoverCooldown: 1.0)
            )
            arbiter.setMain("mouse")
            arbiter.startInterim("trackpad")

            let adoptAt = second + 1_100 * ms
            suite.check(arbiter.canAdoptInterim(at: adoptAt), "can adopt")
            suite.equal(arbiter.adoptInterim(at: adoptAt), "trackpad")
            suite.equal(arbiter.mainDeviceID, "trackpad")
            suite.check(arbiter.interimDeviceID == nil, "interim cleared")
            suite.check(!arbiter.cooldownElapsed(at: adoptAt + 500 * ms), "cooldown active")
            suite.check(arbiter.cooldownElapsed(at: adoptAt + 1_000 * ms), "cooldown elapsed")
        }

        suite.run("the handover delay is the quiet time after the last movement") {
            var arbiter = InterimCursorArbiter(
                policy: InterimCursorPolicy(handoverCooldown: 1.0)
            )
            arbiter.setMain("mouse")
            arbiter.startInterim("trackpad")
            arbiter.noteMovement("trackpad", at: second)

            suite.check(!arbiter.canAdoptInterim(at: second + 500 * ms), "still in delay")
            suite.check(arbiter.canAdoptInterim(at: second + 1_000 * ms), "delay elapsed")
        }

        suite.run("the cooldown blocks a rapid second handover") {
            var arbiter = InterimCursorArbiter(
                policy: InterimCursorPolicy(handoverCooldown: 0.8)
            )
            arbiter.setMain("mouse")
            arbiter.startInterim("trackpad")
            arbiter.adoptInterim(at: second)

            arbiter.noteMovement("mouse", at: second + 100 * ms)
            arbiter.startInterim("mouse")
            suite.check(!arbiter.canAdoptInterim(at: second + 500 * ms), "blocked by cooldown")
            suite.check(arbiter.canAdoptInterim(at: second + 900 * ms), "allowed after cooldown")
        }

        suite.run("a zero cooldown allows an immediate handover") {
            var arbiter = InterimCursorArbiter(
                policy: InterimCursorPolicy(handoverCooldown: 0)
            )
            arbiter.setMain("mouse")
            arbiter.startInterim("trackpad")
            arbiter.adoptInterim(at: second)
            arbiter.startInterim("mouse")
            suite.check(arbiter.canAdoptInterim(at: second), "zero delay")
        }

        suite.run("disabled policy keeps normal switching") {
            var arbiter = InterimCursorArbiter(
                policy: InterimCursorPolicy(isEnabled: false)
            )
            arbiter.setMain("mouse")
            arbiter.noteMovement("mouse", at: second)
            suite.check(
                !arbiter.canStartInterim(for: "trackpad", at: second + 10 * ms),
                "disabled"
            )
        }

        suite.run("setting a new main clears a matching interim cursor") {
            var arbiter = InterimCursorArbiter()
            arbiter.startInterim("trackpad")
            arbiter.setMain("trackpad")
            suite.check(arbiter.interimDeviceID == nil, "interim cleared")
        }

        suite.run("out-of-order movements do not rewind the clock") {
            var arbiter = InterimCursorArbiter()
            arbiter.noteMovement("mouse", at: second + 100 * ms)
            arbiter.noteMovement("mouse", at: second)
            suite.equal(arbiter.lastMovement(for: "mouse"), second + 100 * ms)
        }

        suite.run("reset clears every role") {
            var arbiter = InterimCursorArbiter()
            arbiter.setMain("mouse")
            arbiter.startInterim("trackpad")
            arbiter.adoptInterim(at: second)
            arbiter.reset()
            suite.check(arbiter.mainDeviceID == nil, "main cleared")
            suite.check(arbiter.interimDeviceID == nil, "interim cleared")
            suite.check(arbiter.lastHandoverAt == nil, "cooldown cleared")
        }
    }
}

// MARK: - Attribution

enum AttributionTests {
    static let ms: UInt64 = 1_000_000
    static let base: UInt64 = 1_000_000_000

    static func run(_ suite: TestSuite) {
        print("Attribution")

        suite.run("recent report is attributed") {
            var table = ActivityTable()
            table.record(deviceID: "mouse", timestamp: base, isMovement: true)
            suite.equal(table.device(forEventAt: base + 8 * ms)?.deviceID, "mouse")
        }

        suite.run("report outside the window is ignored") {
            var table = ActivityTable()
            table.record(deviceID: "mouse", timestamp: base, isMovement: true)
            suite.check(table.device(forEventAt: base + 26 * ms) == nil, "outside attribution window")
        }

        suite.run("event before report is accepted within tolerance") {
            var table = ActivityTable()
            table.record(deviceID: "mouse", timestamp: base + ms, isMovement: true)
            suite.equal(table.device(forEventAt: base)?.deviceID, "mouse")
            suite.check(table.device(forEventAt: base - 5 * ms) == nil, "outside future tolerance")
        }

        suite.run("newest report wins") {
            var table = ActivityTable()
            table.record(deviceID: "mouse", timestamp: base, isMovement: true)
            table.record(deviceID: "trackpad", timestamp: base + 10 * ms, isMovement: true)
            suite.equal(table.device(forEventAt: base + 12 * ms)?.deviceID, "trackpad")
        }

        suite.run("an older out-of-order report does not replace a newer one") {
            var table = ActivityTable()
            table.record(deviceID: "mouse", timestamp: base + 10 * ms, isMovement: true)
            table.record(deviceID: "mouse", timestamp: base, isMovement: true)
            suite.equal(table.device(forEventAt: base + 12 * ms)?.deviceID, "mouse")
        }

        suite.run("remove and clear") {
            var table = ActivityTable()
            table.record(deviceID: "mouse", timestamp: base, isMovement: true)
            table.remove(deviceID: "mouse")
            suite.check(table.device(forEventAt: base) == nil, "removed device")
            table.record(deviceID: "mouse", timestamp: base, isMovement: true)
            table.clear()
            suite.check(table.trackedDeviceIDs.isEmpty, "cleared table")
        }
    }
}

// MARK: - Persistence model

enum PersistedStateTests {
    static func run(_ suite: TestSuite) {
        print("PersistedState")

        suite.run("settings and anchors round trip") {
            var state = PersistedState()
            state.automaticSwitching = false
            state.onboardingCompleted = true
            state.update(deviceID: "mouse") { settings in
                settings.assignment = DisplayAssignment(displayUUID: "display-uuid", displayName: "DELL")
                settings.isEnabled = true
                settings.anchor = CursorAnchor(displayUUID: "display-uuid", displayName: "DELL", x: 0.25, y: 0.75)
                settings.lastKnownName = "USB Optical Mouse"
                settings.lastKnownKind = .mouse
            }

            do {
                let data = try JSONEncoder().encode(state)
                let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
                suite.equal(decoded, state)
            } catch {
                suite.check(false, "round trip threw \(error)")
            }
        }

        suite.run("old state without device metadata decodes") {
            let json = """
            {
              "schemaVersion": 1,
              "automaticSwitching": true,
              "onboardingCompleted": true,
              "devices": {
                "mouse": {
                  "assignment": { "displayUUID": null },
                  "isEnabled": true
                }
              }
            }
            """
            do {
                let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
                let settings = decoded.settings(for: "mouse")
                suite.check(settings.isEnabled, "isEnabled")
                suite.check(settings.lastKnownName == nil, "lastKnownName")
                suite.check(settings.anchor == nil, "anchor")
            } catch {
                suite.check(false, "decoding threw \(error)")
            }
        }

        suite.run("interim cursor settings round trip") {
            var state = PersistedState()
            state.interimCursorEnabled = false
            state.handoverCooldown = 2.4

            do {
                let data = try JSONEncoder().encode(state)
                let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
                suite.check(!decoded.interimCursorEnabled, "toggle")
                suite.approximate(decoded.handoverCooldown, 2.4)
            } catch {
                suite.check(false, "round trip threw \(error)")
            }
        }

        suite.run("old state defaults the interim cursor settings") {
            let json = """
            {
              "schemaVersion": 1,
              "automaticSwitching": true,
              "onboardingCompleted": true,
              "devices": {}
            }
            """
            do {
                let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
                suite.check(decoded.interimCursorEnabled, "enabled by default")
                suite.approximate(decoded.handoverCooldown, 0.8)
            } catch {
                suite.check(false, "decoding threw \(error)")
            }
        }

        suite.run("missing device uses defaults") {
            let state = PersistedState()
            let settings = state.settings(for: "unknown")
            suite.check(settings.isEnabled, "enabled by default")
            suite.check(settings.assignment.displayUUID == nil, "unmanaged by default")
            suite.check(settings.anchor == nil, "no anchor by default")
        }

        suite.run("migrates settings to a new connection ID") {
            var state = PersistedState()
            state.update(deviceID: "hid:046d:c077:loc:1130000") { settings in
                settings.assignment = DisplayAssignment(displayUUID: "dell", displayName: "DELL")
                settings.anchor = CursorAnchor(displayUUID: "dell", x: 0.5, y: 0.5)
                settings.lastKnownName = "USB Optical Mouse"
                settings.lastKnownKind = .mouse
            }

            let migrated = state.migrateSettings(
                from: "hid:046d:c077:loc:1130000",
                to: "hid:046d:c077:loc:130000"
            )
            suite.check(migrated, "migration reported")
            suite.check(state.devices["hid:046d:c077:loc:1130000"] == nil, "old key removed")
            let settings = state.settings(for: "hid:046d:c077:loc:130000")
            suite.equal(settings.assignment.displayUUID, "dell")
            suite.check(settings.anchor != nil, "anchor moved")
            suite.equal(settings.lastKnownName, "USB Optical Mouse")
        }

        suite.run("migration keeps the newer anchor and assignment") {
            var state = PersistedState()
            state.update(deviceID: "old") { settings in
                settings.assignment = DisplayAssignment(displayUUID: "old-display")
                settings.anchor = CursorAnchor(displayUUID: "old-display", x: 0.1, y: 0.1)
            }
            state.update(deviceID: "new") { settings in
                settings.assignment = DisplayAssignment(displayUUID: "new-display")
                settings.anchor = CursorAnchor(displayUUID: "new-display", x: 0.9, y: 0.9)
            }

            let migrated = state.migrateSettings(from: "old", to: "new")
            suite.check(migrated, "migration reported")
            let settings = state.settings(for: "new")
            suite.equal(settings.assignment.displayUUID, "new-display")
            suite.equal(settings.anchor?.x, 0.9)
            suite.check(!state.migrateSettings(from: "missing", to: "new"), "missing source ignored")
            suite.check(!state.migrateSettings(from: "new", to: "new"), "same identity ignored")
        }
    }
}

// MARK: - Device model

enum PointingDeviceTests {
    static func run(_ suite: TestSuite) {
        print("PointingDevice")

        suite.run("managed requires connection, enablement and assignment") {
            var device = PointingDevice(id: "mouse", name: "Mouse", kind: .mouse)
            suite.check(!device.isManaged, "unmanaged by default")

            device.assignment = DisplayAssignment(displayUUID: "display")
            suite.check(device.isManaged, "assigned device is managed")

            device.isConnected = false
            suite.check(!device.isManaged, "disconnected device is not managed")

            device.isConnected = true
            device.isEnabled = false
            suite.check(!device.isManaged, "disabled device is not managed")
        }

        suite.run("assignment description") {
            var device = PointingDevice(id: "mouse", name: "Mouse", kind: .mouse)
            suite.equal(device.assignmentDescription, "Unmanaged")
            device.assignment = DisplayAssignment(displayUUID: "uuid", displayName: "DELL S2725QS")
            suite.equal(device.assignmentDescription, "DELL S2725QS")
        }
    }
}
