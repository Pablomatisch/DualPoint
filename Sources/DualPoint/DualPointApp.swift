import SwiftUI
import AppKit
import DualPointCore

@main
struct DualPointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: .shared, engine: AppModel.shared.engine)
                .environmentObject(AppModel.shared)
        } label: {
            Label("DualPoint", systemImage: "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
