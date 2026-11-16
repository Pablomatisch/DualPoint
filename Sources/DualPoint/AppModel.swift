import Foundation
import AppKit
import Combine
import SwiftUI
import DualPointCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case devices
    case activity
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .devices: return "Devices"
        case .activity: return "Activity"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "switch.2"
        case .devices: return "computermouse"
        case .activity: return "waveform.path.ecg"
        case .about: return "info.circle"
        }
    }
}

/// Owns the app-wide engine and the two standalone AppKit windows (Settings and
/// Setup). A single shared instance is used by the SwiftUI scene and the
/// application delegate.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let engine = DualPointEngine()
    @Published var settingsTab: SettingsTab = .general
    @Published private(set) var loginItemStatus: LoginItemManager.Status = .disabled
    @Published var loginItemError: String?

    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var hasStarted = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        engine.start()
        refreshLoginItem()

        if !engine.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openOnboarding()
            }
        }
    }

    func stop() {
        guard hasStarted else { return }
        hasStarted = false
        engine.stop()
    }

    func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Windows

    func openSettings(tab: SettingsTab = .general) {
        StatusItemController.shared.hide()
        settingsTab = tab

        if let controller = settingsWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsView(model: self, engine: engine)
            .environmentObject(self)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        let window = makeWindow(
            title: "DualPoint Settings",
            size: NSSize(width: 920, height: 640),
            minSize: NSSize(width: 860, height: 600),
            autosaveName: "DualPointSettingsWindow"
        )
        window.contentViewController = hosting

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func openOnboarding() {
        StatusItemController.shared.hide()
        if let controller = onboardingWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = OnboardingView(
            model: self,
            engine: engine,
            onFinish: { [weak self] in self?.closeOnboarding() }
        )
        .environmentObject(self)
        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        let window = makeWindow(
            title: "Welcome to DualPoint",
            size: NSSize(width: 780, height: 760),
            minSize: NSSize(width: 740, height: 700),
            autosaveName: "DualPointOnboardingWindow"
        )
        window.contentViewController = hosting

        let controller = NSWindowController(window: window)
        onboardingWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A borderless-feeling window: transparent title bar, dark glass content
    /// extending edge to edge, and the system traffic lights kept for closing.
    private func makeWindow(
        title: String,
        size: NSSize,
        minSize: NSSize,
        autosaveName: String
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(size)
        window.minSize = minSize
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        return window
    }

    private func closeOnboarding() {
        engine.setTestDriving(false)
        onboardingWindowController?.window?.close()
        onboardingWindowController = nil
    }

    // MARK: - Login item

    func refreshLoginItem() {
        loginItemStatus = LoginItemManager.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.setEnabled(enabled)
            loginItemError = nil
            refreshLoginItem()
            engine.log.info("Login Item", enabled ? "Enabled" : "Disabled")
        } catch {
            loginItemError = error.localizedDescription
            refreshLoginItem()
            engine.log.error("Login Item", error.localizedDescription)
        }
    }

    // MARK: - Support actions

    func copyDiagnostics() {
        let text = engine.log.recentText(limit: 250)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func revealStateFile() {
        NSWorkspace.shared.activateFileViewerSelecting([engine.store.fileURL])
    }

    func revealLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([engine.log.fileURL])
    }
}
