import SwiftUI
import AppKit
import DualPointCore

@main
struct DualPointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("DualPoint")
                    .font(.headline)
                Text("Independent cursor positions for every pointing device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Button("Quit DualPoint") {
                    NSApp.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 300)
        } label: {
            Label("DualPoint", systemImage: "cursorarrow.rays")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
