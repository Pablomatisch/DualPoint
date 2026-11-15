import SwiftUI
import AppKit
import DualPointCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)

            Divider()

            ScrollView {
                content
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            model.refreshLoginItem()
            engine.refreshPermissions()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandIcon(size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DualPoint")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Version \(DualPointCore.version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            StatusPill(text: engine.statusSummary, color: engine.statusColor)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 12)

            VStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarButton(tab)
                }
            }
            .padding(8)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text("One cursor. Every device.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("No Dock icon · macOS 13+")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func sidebarButton(_ tab: SettingsTab) -> some View {
        let selected = model.settingsTab == tab
        return Button {
            model.settingsTab = tab
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 17)
                    .foregroundStyle(selected ? Brand.accent : .secondary)
                Text(tab.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Brand.accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch model.settingsTab {
        case .general:
            GeneralSettingsTab(model: model, engine: engine)
        case .devices:
            DevicesSettingsTab(model: model, engine: engine)
        case .activity:
            ActivitySettingsTab(engine: engine)
        case .about:
            AboutSettingsTab()
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                title: "General",
                subtitle: "Automatic switching, permissions and launch behavior."
            )

            SettingsCard(
                title: "Cursor switching",
                subtitle: "DualPoint restores a device's last position when you start using it."
            ) {
                Toggle(isOn: Binding(
                    get: { engine.automaticSwitching },
                    set: { engine.setAutomaticSwitching($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically switch cursor position")
                            .font(.system(size: 12, weight: .medium))
                        Text("Turn this off to keep the cursor where it is. Positions are still remembered.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Circle()
                        .fill(engine.statusColor)
                        .frame(width: 7, height: 7)
                    Text(engine.statusSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !engine.hasCompletedOnboarding {
                        Button("Run Setup") { model.openOnboarding() }
                            .controlSize(.small)
                    }
                }
            }

            SettingsCard(
                title: "Setup",
                subtitle: "The setup assistant explains permissions and assigns each device to a display."
            ) {
                HStack {
                    StatusRow(
                        title: engine.hasCompletedOnboarding ? "Setup complete" : "Setup not finished",
                        detail: engine.hasCompletedOnboarding
                            ? "You can run the assistant again at any time."
                            : "Automatic switching stays paused until setup is complete.",
                        isGood: engine.hasCompletedOnboarding
                    )
                }

                HStack(spacing: 8) {
                    Button("Run Setup Assistant") { model.openOnboarding() }
                    if engine.hasCompletedOnboarding {
                        Button("Reset Setup") { engine.resetOnboarding() }
                            .foregroundStyle(.red)
                    }
                }
                .controlSize(.small)
            }

            SettingsCard(
                title: "Permissions",
                subtitle: "Input Monitoring is the only permission required for normal operation."
            ) {
                StatusRow(
                    title: "Input Monitoring",
                    detail: engine.permissions.hidAccessGranted && engine.permissions.listenEventAccessGranted
                        ? "Granted. DualPoint can identify pointing devices."
                        : "Required to identify which physical device moved.",
                    isGood: engine.permissions.hidAccessGranted && engine.permissions.listenEventAccessGranted
                )

                StatusRow(
                    title: "Pointer event monitoring",
                    detail: engine.eventTapFailure
                        ?? (engine.permissions.eventTapAvailable
                            ? "Listening for pointer activity. Events are never modified."
                            : "Unavailable until Input Monitoring is granted."),
                    isGood: engine.permissions.eventTapAvailable
                )

                StatusRow(
                    title: "Accessibility",
                    detail: engine.permissions.accessibilityTrusted
                        ? "Granted, but not normally needed."
                        : "Only needed if macOS refuses the listen-only event tap.",
                    isGood: engine.permissions.accessibilityTrusted
                )

                HStack(spacing: 8) {
                    Button("Grant Input Monitoring") { engine.requestInputMonitoring() }
                    Button("Open System Settings") { engine.openInputMonitoringSettings() }
                    Button("Check Again") { engine.refreshPermissions() }
                    if !engine.permissions.eventTapAvailable && engine.permissions.listenEventAccessGranted {
                        Button("Request Accessibility") { engine.requestAccessibility() }
                    }
                }
                .controlSize(.small)

                Text("Permission is tied to the app's signature. Rebuilding an ad-hoc signed copy may require granting it again.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(
                title: "Launch at login",
                subtitle: "DualPoint runs quietly in the menu bar without a Dock icon."
            ) {
                Toggle(isOn: Binding(
                    get: { model.loginItemStatus.isOn },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Text("Open DualPoint at login")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .disabled(model.loginItemStatus == .notFound)

                HStack(spacing: 6) {
                    Text("Status: \(model.loginItemStatus.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.loginItemStatus == .requiresApproval || model.loginItemStatus == .notFound {
                        Button("Open Login Items") { engine.openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                }

                if let error = model.loginItemError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.loginItemStatus == .notFound {
                    Text("Move DualPoint.app to /Applications to enable login launch.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            SettingsCard(
                title: "Files",
                subtitle: "Everything DualPoint stores is human-readable and local to this Mac."
            ) {
                HStack(spacing: 8) {
                    Button("Reveal Saved State") { model.revealStateFile() }
                    Button("Reveal Log") { model.revealLogFile() }
                    Button("Copy Diagnostics") { model.copyDiagnostics() }
                }
                .controlSize(.small)

                Text(engine.store.fileURL.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - Devices

private struct DevicesSettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                header(
                    title: "Devices",
                    subtitle: "Choose the display each physical pointing device belongs to."
                )
                Spacer()
                Button("Apply Recommended") {
                    engine.applyRecommendedSetup()
                }
                .controlSize(.small)
                .disabled(engine.connectedDevices.isEmpty)
            }

            Text("The last cursor position always wins. The display assignment is used the first time a device is used, after resetting its position, or when its previous display is disconnected.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if engine.devices.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No pointing devices found")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Grant Input Monitoring, then use “Check Again” on the General tab.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(engine.devices) { device in
                        DeviceSettingsRow(engine: engine, device: device)
                    }
                }
            }

            SettingsCard(
                title: "Displays",
                subtitle: "Detected automatically. Arrangement, scaling and disconnection are handled live."
            ) {
                if engine.displays.isEmpty {
                    Text("No active displays.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(engine.displays) { display in
                        HStack(spacing: 10) {
                            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                .font(.system(size: 13))
                                .foregroundStyle(Brand.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Text(display.name)
                                        .font(.system(size: 12, weight: .medium))
                                    if display.isMain {
                                        tag("Main")
                                    }
                                    if display.isBuiltIn {
                                        tag("Built-in")
                                    }
                                }
                                Text("\(display.detailLabel) · \(Int(display.bounds.width)) × \(Int(display.bounds.height)) pt")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            HStack {
                Button("Reset All Saved Positions") {
                    engine.resetAllPositions()
                }
                .controlSize(.small)
                Spacer()
                Text("\(engine.managedDevices.count) of \(engine.connectedDevices.count) connected devices managed")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(Brand.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Brand.accent.opacity(0.12)))
    }
}

private struct DeviceSettingsRow: View {
    @ObservedObject var engine: DualPointEngine
    let device: PointingDevice

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(device.isActive ? Brand.accent.opacity(0.16) : Color.primary.opacity(0.055))
                    .frame(width: 36, height: 36)
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(device.isActive ? Brand.accent : .secondary)
            }
            .opacity(device.isConnected ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if device.isActive {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(Brand.success)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Brand.success.opacity(0.12)))
                    }
                }
                HStack(spacing: 6) {
                    Text(device.connectionLabel)
                    if !device.identityDescription.isEmpty {
                        Text("·")
                        Text(device.identityDescription)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if device.hasSavedPosition && device.isConnected {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.accent.opacity(0.65))
                    .help("A saved cursor position exists for this device")
            }

            Toggle("", isOn: Binding(
                get: { device.isEnabled },
                set: { engine.setEnabled(deviceID: device.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!device.isConnected)
            .help(device.isEnabled ? "Disable this device" : "Enable this device")

            AssignmentMenu(engine: engine, device: device)
                .frame(minWidth: 120, alignment: .trailing)

            Menu {
                Button("Move Cursor Now") {
                    engine.activate(deviceID: device.id)
                }
                .disabled(!device.isConnected || !device.isEnabled || (!device.isManaged && !device.hasSavedPosition))

                Button("Reset Saved Position") {
                    engine.resetPosition(deviceID: device.id)
                }
                .disabled(!device.hasSavedPosition)

                if !device.isConnected {
                    Divider()
                    Button("Forget Device", role: .destructive) {
                        engine.forgetDevice(deviceID: device.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(device.isActive ? Brand.accent.opacity(0.35) : Color.primary.opacity(0.07))
        )
        .opacity(device.isConnected ? 1 : 0.7)
    }
}

// MARK: - Activity

private struct ActivitySettingsTab: View {
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(
                title: "Activity",
                subtitle: "A record of switches, devices and display changes. No movement data or keystrokes."
            )

            if let lastSwitch = engine.lastSwitch {
                SettingsCard(title: "Last switch") {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lastSwitch.deviceName)
                                .font(.system(size: 14, weight: .semibold))
                            Text(lastSwitch.at.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if lastSwitch.wasWarped {
                            Label("Cursor restored", systemImage: "arrow.left.arrow.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Brand.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Brand.accent.opacity(0.12)))
                        }
                        if let point = lastSwitch.restoredPoint {
                            Text(String(format: "(%.0f, %.0f)", point.x, point.y))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsCard(
                title: "Log",
                subtitle: "Also written to \(engine.log.fileURL.path)"
            ) {
                LogListView(log: engine.log)
                    .frame(height: 260)

                HStack(spacing: 8) {
                    Button("Clear") { engine.log.clear() }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(engine.log.recentText(limit: 250), forType: .string)
                    }
                    Button("Reveal Log") {
                        NSWorkspace.shared.activateFileViewerSelecting([engine.log.fileURL])
                    }
                    Spacer()
                    Text("\(engine.log.entries.count) entries")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .controlSize(.small)
            }

            HStack {
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(engine.log.recentText(limit: 250), forType: .string)
                }
                .controlSize(.small)
                Spacer()
            }
        }
    }
}

private struct LogListView: View {
    @ObservedObject var log: DiagnosticLog

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if log.entries.isEmpty {
                    Text("No activity recorded yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(8)
                } else {
                    ForEach(log.entries.suffix(250)) { entry in
                        Text(entry.line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)

            BrandIcon(size: 96)

            VStack(spacing: 5) {
                Text("DualPoint")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Version \(DualPointCore.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Independent cursor positions for every pointing device.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            StatusPill(text: "One real system cursor", color: Brand.accent)

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    aboutLine("cursorarrow.rays", "Each device keeps its own last cursor position.")
                    aboutLine("display", "Assign devices to the built-in or any external display.")
                    aboutLine("lock.shield", "No keystroke logging, no private APIs, no network access.")
                    aboutLine("menubar.rectangle", "Lives in the menu bar with no Dock icon.")
                }
            }
            .frame(maxWidth: 430)

            Spacer()

            Text("Copyright © 2026 DualPoint. All rights reserved.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func aboutLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.accent)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared header

private func header(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.system(size: 20, weight: .bold, design: .rounded))
        Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
