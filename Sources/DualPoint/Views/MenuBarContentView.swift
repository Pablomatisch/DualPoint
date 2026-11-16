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
            DividerLine()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    notices

                    SectionLabel(
                        text: "Devices",
                        trailing: connectedDevices.isEmpty ? nil : "\(connectedDevices.count) devices"
                    )

                    if connectedDevices.isEmpty {
                        emptyDevices
                    } else {
                        VStack(spacing: 7) {
                            ForEach(connectedDevices) { device in
                                MenuDeviceRow(engine: engine, device: device)
                            }
                        }
                    }

                    deviceActions
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(width: PanelMetrics.contentWidth, height: PanelMetrics.contentHeight)
        .background(PanelBackground(cornerRadius: PanelMetrics.cornerRadius))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            BrandIcon(size: 38, glow: engine.isSwitchingEnabled)

            Text("DualPoint")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)

            Spacer(minLength: 6)

            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(GlassIconButtonStyle(size: 32))
            .help("Open DualPoint Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 13)
        .background(
            LinearGradient(
                colors: [Brand.accent.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Notices

    @ViewBuilder
    private var notices: some View {
        if needsPermission {
            PermissionNotice(engine: engine, compact: true)
        } else if !engine.hasCompletedOnboarding {
            banner(
                symbol: "wand.and.stars",
                color: Brand.accent,
                title: "Finish setting up DualPoint",
                detail: "Choose a display for each device.",
                actionTitle: "Continue"
            ) {
                model.openOnboarding()
            }
        } else if !engine.isSwitchingEnabled {
            banner(
                symbol: "pause.fill",
                color: Brand.warning,
                title: "Switching is paused",
                detail: engine.statusSummary,
                actionTitle: "Fix"
            ) {
                model.openSettings(tab: .general)
            }
        }
    }

    private func banner(
        symbol: String,
        color: Color,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(actionTitle, action: action)
                .buttonStyle(SecondaryButtonStyle(compact: true))
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Devices

    private var emptyDevices: some View {
        HStack(spacing: 10) {
            Image(systemName: needsPermission ? "lock.fill" : "computermouse")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Brand.textTertiary)
            Text(needsPermission
                 ? "Grant Input Monitoring to see connected devices."
                 : "No pointing devices detected.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private var deviceActions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button("Manage Devices") {
                model.openSettings(tab: .devices)
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Brand.accent.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Switch automatically")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                }

                Spacer(minLength: 4)

                Toggle("", isOn: Binding(
                    get: { engine.automaticSwitching },
                    set: { engine.setAutomaticSwitching($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Brand.accent)
                .controlSize(.mini)
            }

            DividerLine()

            HStack(spacing: 8) {
                Button {
                    model.openSettings()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))

                Button {
                    model.openOnboarding()
                } label: {
                    Label("Setup", systemImage: "wand.and.stars")
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))

                Spacer(minLength: 0)

                Button {
                    model.quit()
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(GlassIconButtonStyle(size: 30))
                .help("Quit DualPoint")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 15)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.10), Color.black.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) { DividerLine() }
    }
}

private struct MenuDeviceRow: View {
    @ObservedObject var engine: DualPointEngine
    let device: PointingDevice

    var body: some View {
        HoverCard(active: device.isActive, cornerRadius: 14) {
            HStack(spacing: 10) {
                DeviceGlyph(symbol: device.kind.symbol, active: device.isActive, size: 33)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary)
                            .lineLimit(1)

                        if !device.isEnabled {
                            PillTag(text: "Off", color: Brand.textTertiary)
                        }
                    }

                    Text(device.connectionLabel)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Brand.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                AssignmentMenu(engine: engine, device: device)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}
