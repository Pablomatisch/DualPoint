import AppKit
import SwiftUI
import DualPointCore

#if DEBUG
/// Development-only offscreen renderer used to review the interface without
/// Screen Recording permission. Enabled by setting DUALPOINT_SNAPSHOT_DIR.
@MainActor
enum SnapshotRunner {
    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["DUALPOINT_SNAPSHOT_DIR"] else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var isRequested: Bool { directory != nil }

    static func captureIfRequested(model: AppModel) {
        guard let directory else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            capture(
                MenuBarContentView(model: model, engine: model.engine),
                size: CGSize(width: PanelMetrics.contentWidth, height: PanelMetrics.contentHeight),
                named: "panel",
                in: directory
            )

            let tabs: [SettingsTab] = [.general, .devices, .activity, .about]
            for tab in tabs {
                model.settingsTab = tab
                capture(
                    SettingsView(model: model, engine: model.engine),
                    size: CGSize(width: 920, height: 640),
                    named: "settings-\(tab.rawValue)",
                    in: directory
                )
            }

            capture(
                OnboardingView(model: model, engine: model.engine, onFinish: {}),
                size: CGSize(width: 780, height: 760),
                named: "onboarding",
                in: directory
            )

            for step in 0..<4 {
                capture(
                    OnboardingView(model: model, engine: model.engine, initialStep: step, onFinish: {}),
                    size: CGSize(width: 780, height: 760),
                    named: "onboarding-\(step + 1)",
                    in: directory
                )
            }

            NSApp.terminate(nil)
        }
    }

    private static func capture<V: View>(_ root: V, size: CGSize, named name: String, in directory: URL) {
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("Snapshot: no bitmap for \(name)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("Snapshot: no PNG for \(name)")
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            print("Snapshot: \(url.path)")
        } catch {
            print("Snapshot: \(error)")
        }
    }
}
#endif
