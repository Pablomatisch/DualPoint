import Foundation
import AppKit
import ApplicationServices
import IOKit.hid
import CoreGraphics

/// Centralizes the two TCC permissions DualPoint can need.
///
/// * **Input Monitoring** lets DualPoint open HID devices for input reports and
///   listen to system pointer events. It is the only permission required for
///   normal operation.
/// * **Accessibility** is only requested if macOS refuses to create the
///   listen-only event tap even though Input Monitoring is granted.
public enum PermissionCenter {
    public static func snapshot(eventTapAvailable: Bool) -> PermissionSnapshot {
        PermissionSnapshot(
            hidAccessGranted: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
            listenEventAccessGranted: CGPreflightListenEventAccess(),
            eventTapAvailable: eventTapAvailable,
            accessibilityTrusted: AXIsProcessTrusted()
        )
    }

    /// Asks macOS for Input Monitoring. The system only shows a prompt once per
    /// bundle; afterwards the user must enable DualPoint in System Settings.
    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        let hidGranted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        let listenGranted = CGRequestListenEventAccess()
        return hidGranted && listenGranted
    }

    /// Shows the Accessibility prompt. Only needed in the rare case where macOS
    /// refuses the listen-only event tap even though Input Monitoring is on.
    @discardableResult
    public static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openLoginItemsSettings() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    public static func quitAndReopen() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                NSLog("DualPoint: could not relaunch: \(error)")
                return
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
