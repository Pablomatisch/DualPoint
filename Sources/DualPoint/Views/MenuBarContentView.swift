import SwiftUI
import DualPointCore

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine

    private var needsPermission: Bool {
        !engine.permissions.hidAccessGranted || !engine.permissions.listenEventAccessGranted
    }

    private var connectedDevices: [PointingDevice] {
        engine.devices.filter(\.isConnected)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if needsPermission {
                        PermissionNotice(engine: engine)
                    } else if !engine.hasCompletedOnboarding {
                        setupNotice
                    } else if !engine.isSwitchingEnabled {
                        pausedNotice
                    }

                    ActiveDeviceCard(engine: engine)

                    deviceSection

                    if engine.lastSwitch != nil {
                        switchFootnote
                    }
                }
                .padding(12)
            }
            .frame(minHeight: 220, maxHeight: 420)

            Divider()
            footer
        }
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 11) {
            BrandIcon(size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("DualPoint")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                StatusPill(text: engine.statusSummary, color: engine.statusColor)
            }

            Spacer()

            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open DualPoint Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Brand.softGradient)
    }

    private var setupNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Brand.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Finish setting up DualPoint")
                    .font(.system(size: 12, weight: .semibold))
                Text("Choose a display for each device.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Continue") { model.openOnboarding() }
                .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Brand.accent.opacity(0.10))
        )
    }

    private var pausedNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.secondary)
            Text(engine.statusSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Fix") { model.openSettings(tab: .general) }
                .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("DEVICES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(connectedDevices.count) connected")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if connectedDevices.isEmpty {
                Text(needsPermission
                     ? "Grant Input Monitoring to see connected devices."
                     : "No pointing devices detected.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(connectedDevices) { device in
                    MenuDeviceRow(engine: engine, device: device)
                }
            }

            HStack(spacing: 8) {
                Button("Apply Recommended") {
                    engine.applyRecommendedSetup()
                }
                .controlSize(.small)
                .disabled(connectedDevices.isEmpty)

                Button("Reset Positions") {
                    engine.resetAllPositions()
                }
                .controlSize(.small)

                Spacer()

                Button("Manage…") {
                    model.openSettings(tab: .devices)
                }
                .controlSize(.small)
            }
            .padding(.top, 3)
        }
    }

    private var switchFootnote: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9))
            if let lastSwitch = engine.lastSwitch {
                Text("Last switch \(lastSwitch.at, style: .relative) ago · \(lastSwitch.deviceName)")
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Toggle(isOn: Binding(
                get: { engine.automaticSwitching },
                set: { engine.setAutomaticSwitching($0) }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Automatic switching")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack(spacing: 10) {
                Button {
                    model.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    model.openOnboarding()
                } label: {
                    Label("Setup", systemImage: "wand.and.stars")
                }
                Spacer()
                Button("Quit") {
                    model.quit()
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct MenuDeviceRow: View {
    @ObservedObject var engine: DualPointEngine
    let device: PointingDevice

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(device.isActive ? Brand.accent.opacity(0.16) : Color.primary.opacity(0.055))
                    .frame(width: 28, height: 28)
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(device.isActive ? Brand.accent : .secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if device.isActive {
                        Circle()
                            .fill(Brand.success)
                            .frame(width: 5, height: 5)
                            .help("Currently active")
                    }
                    if !device.isEnabled {
                        Text("Off")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(device.connectionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            AssignmentMenu(engine: engine, device: device, compact: true)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(device.isActive ? Brand.accent.opacity(0.065) : Color.clear)
        )
    }
}
