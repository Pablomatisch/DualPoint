import SwiftUI
import AppKit
import DualPointCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        ZStack {
            WindowBackground()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 228)

                contentArea
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .preferredColorScheme(.dark)
        .onAppear {
            model.refreshLoginItem()
            engine.refreshPermissions()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                BrandIcon(size: 40, glow: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DualPoint")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Version \(DualPointCore.version)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Brand.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 46)
            .padding(.bottom, 12)

            StatusPill(text: engine.statusSummary, color: engine.statusColor)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)

            DividerLine()
                .padding(.horizontal, 14)

            SectionLabel(text: "Settings")
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    SidebarItem(
                        tab: tab,
                        selected: model.settingsTab == tab,
                        badge: tab == .devices ? "\(engine.connectedDevices.count)" : nil
                    ) {
                        model.settingsTab = tab
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            if !engine.hasCompletedOnboarding {
                setupCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
            }
        }
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blending: .withinWindow, emphasized: false)
                Color.black.opacity(0.16)
                LinearGradient(
                    colors: [Brand.accent.opacity(0.06), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                Text("Finish setup")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
            }
            Text("Assign each device to a display.")
                .font(.system(size: 9.5))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Setup") {
                model.openOnboarding()
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Brand.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.cardEdge, lineWidth: 1)
        )
    }

    // MARK: - Content

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ScreenHeader(
                        title: model.settingsTab.title,
                        subtitle: model.settingsTab.subtitle
                    )
                    Spacer(minLength: 12)
                    if model.settingsTab == .devices {
                        Button("Apply Recommended") {
                            engine.applyRecommendedSetup()
                        }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                        .disabled(engine.connectedDevices.isEmpty)
                    }
                }

                ZStack(alignment: .topLeading) {
                    tabContent
                        .id(model.settingsTab)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 10)),
                                removal: .opacity
                            )
                        )
                }
                .animation(.easeOut(duration: 0.22), value: model.settingsTab)
            }
            .padding(.horizontal, 30)
            .padding(.top, 46)
            .padding(.bottom, 32)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch model.settingsTab {
        case .general:
            GeneralSettingsTab(model: model, engine: engine)
        case .devices:
            DevicesSettingsTab(model: model, engine: engine)
        case .activity:
            ActivitySettingsTab(model: model, engine: engine)
        case .about:
            AboutSettingsTab()
        }
    }
}

private extension SettingsTab {
    var subtitle: String {
        switch self {
        case .general: return "Switching, permissions and launch."
        case .devices: return "Choose where each device belongs."
        case .activity: return "Recent switches and device events."
        case .about: return "Version, privacy and files."
        }
    }
}

// MARK: - Sidebar item

private struct SidebarItem: View {
    let tab: SettingsTab
    let selected: Bool
    let badge: String?
    let action: () -> Void

    @StateObject private var hover = HoverStore()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.white : Brand.textSecondary)

                Text(tab.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Brand.textSecondary)

                Spacer(minLength: 4)

                if let badge, badge != "0" {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : Brand.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(selected ? 0.16 : 0.06))
                        )
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: selected
                                ? [Brand.accent.opacity(0.30), Brand.violet.opacity(0.16)]
                                : [Color.white.opacity(hover.isHovering ? 0.07 : 0), Color.white.opacity(0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        selected ? Brand.accent.opacity(0.34) : Color.white.opacity(hover.isHovering ? 0.08 : 0),
                        lineWidth: 1
                    )
            )
            .shadow(color: selected ? Brand.accent.opacity(0.18) : .clear, radius: 10, x: 0, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.isHovering)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine

    private var hasPermission: Bool {
        engine.permissions.hidAccessGranted && engine.permissions.listenEventAccessGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !engine.hasCompletedOnboarding {
                setupBanner
            }

            GlassCard(
                title: "Cursor switching",
                subtitle: "Restores a device's last position when you start using it.",
                symbol: "arrow.left.arrow.right"
            ) {
                Toggle(isOn: Binding(
                    get: { engine.automaticSwitching },
                    set: { engine.setAutomaticSwitching($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch automatically")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Brand.textPrimary)
                        Text("When off, the cursor stays where it is.")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Brand.accent)
            }

            GlassCard(
                title: "Simultaneous cursors",
                subtitle: "Move an external mouse while the trackpad moves. The trackpad keeps the real cursor.",
                symbol: "cursorarrow.rays"
            ) {
                Toggle(isOn: Binding(
                    get: { engine.interimCursorEnabled },
                    set: { engine.setInterimCursorEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show a second cursor")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Brand.textPrimary)
                        Text("An external mouse gets a blue cursor while both devices move.")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Brand.accent)

                if engine.interimCursorEnabled {
                    DividerLine()

                    HStack(spacing: 10) {
                        Text("Handover delay")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Brand.textSecondary)
                        Spacer(minLength: 8)
                        Text(String(format: "%.1f s", engine.handoverCooldown))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Brand.textPrimary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { engine.handoverCooldown },
                            set: { engine.setHandoverCooldown($0) }
                        ),
                        in: 0...3,
                        step: 0.1
                    )
                    .tint(Brand.accent)

                    Text("How long the external mouse and trackpad must both stay still before the blue pointer is removed. Its final position is saved for that mouse; the real cursor stays where the trackpad left it. Raise it if the blue pointer disappears too early.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if engine.interimCursorEnabled && !engine.supportsInterimCursor {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Brand.warning)
                        Text("Input Monitoring is required. Connect an external mouse: only seized external devices can show a second cursor.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            GlassCard(
                title: "Permissions",
                subtitle: "Input Monitoring finds devices and lets DualPoint isolate an external mouse.",
                symbol: "lock.shield.fill"
            ) {
                StatusRow(
                    title: "Input Monitoring",
                    detail: hasPermission
                        ? "Granted."
                        : "Required to identify pointing devices.",
                    isGood: hasPermission
                )

                if !engine.permissions.eventTapAvailable {
                    StatusRow(
                        title: "Pointer monitoring",
                        detail: engine.eventTapFailure ?? "Waiting for Input Monitoring.",
                        isGood: false
                    )
                }

                StatusRow(
                    title: "Accessibility",
                    detail: "Optional. The blue pointer uses raw HID on external devices; the built-in trackpad always owns the real cursor.",
                    isGood: true
                )

                HStack(spacing: 8) {
                    if !hasPermission {
                        Button("Grant Input Monitoring") { engine.requestInputMonitoring() }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                    } else {
                        Button("Open Input Monitoring") { engine.openInputMonitoringSettings() }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                    Button("Check Again") { engine.refreshPermissions() }
                        .buttonStyle(GhostButtonStyle(compact: true))
                    Spacer(minLength: 0)
                }

            }

            GlassCard(
                title: "Launch at login",
                subtitle: "Starts quietly in the menu bar.",
                symbol: "power"
            ) {
                Toggle(isOn: Binding(
                    get: { model.loginItemStatus.isOn },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Text("Open DualPoint at login")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Brand.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(Brand.accent)
                .disabled(model.loginItemStatus == .notFound)

                if model.loginItemStatus != .enabled || model.loginItemError != nil {
                    HStack(spacing: 6) {
                        Text(model.loginItemStatus.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.textSecondary)
                        Spacer()
                        if model.loginItemStatus == .requiresApproval || model.loginItemStatus == .notFound {
                            Button("Open Login Items") { engine.openLoginItemsSettings() }
                                .buttonStyle(GhostButtonStyle(compact: true))
                        }
                    }
                }

                if let error = model.loginItemError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.loginItemStatus == .notFound {
                    Text("Move DualPoint.app to /Applications to enable login launch.")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textTertiary)
                }
            }
        }
    }

    private var setupBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Brand.accent.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Setup is not finished")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Text("Assign each device to a display.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.textSecondary)
            }

            Spacer(minLength: 4)

            Button("Continue") { model.openOnboarding() }
                .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Brand.accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Brand.accent.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Devices

private struct DevicesSettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.accent)
                Text("The last position wins. Assignments apply the first time, after a reset, or when a display disconnects.")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Brand.accent.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Brand.accent.opacity(0.16), lineWidth: 1)
            )

            if engine.devices.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No pointing devices found")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary)
                        Text("Grant Input Monitoring, then use “Check Again” on the General tab.")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
            } else {
                VStack(spacing: 9) {
                    ForEach(engine.devices) { device in
                        DeviceSettingsRow(engine: engine, device: device)
                    }
                }
            }

            GlassCard(
                title: "Displays",
                subtitle: "Updates automatically when displays change.",
                symbol: "display.2"
            ) {
                DisplayMap(
                    displays: engine.displays,
                    activeDisplayID: engine.activeDevice?.assignment.displayUUID
                )

                if !engine.displays.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(engine.displays.enumerated()), id: \.element.id) { index, display in
                            if index > 0 { DividerLine() }
                            HStack(spacing: 10) {
                                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Brand.accent)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text(display.name)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(Brand.textPrimary)
                                        if display.isMain { PillTag(text: "Main") }
                                        if display.isBuiltIn { PillTag(text: "Built-in", color: Brand.cyan) }
                                    }
                                    Text(display.resolutionLabel + (display.scale > 1 ? " · @\(Int(display.scale))×" : ""))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Brand.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 9)
                        }
                    }
                }
            }

            HStack {
                Button("Reset All Saved Positions") {
                    engine.resetAllPositions()
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                Spacer()
                Text("\(engine.managedDevices.count) of \(engine.connectedDevices.count) connected devices managed")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textTertiary)
            }

            let disconnected = engine.devices.filter { !$0.isConnected }
            if !disconnected.isEmpty {
                GlassCard(
                    title: "Previously seen",
                    subtitle: "Keeps settings for the next connection.",
                    symbol: "clock.arrow.circlepath"
                ) {
                    VStack(spacing: 8) {
                        ForEach(disconnected) { device in
                            DeviceSettingsRow(engine: engine, device: device)
                        }
                    }
                }
            }
        }
    }
}

private struct DeviceSettingsRow: View {
    @ObservedObject var engine: DualPointEngine
    let device: PointingDevice

    var body: some View {
        HoverCard(active: device.isActive, cornerRadius: 16) {
            HStack(spacing: 12) {
                DeviceGlyph(symbol: device.kind.symbol, active: device.isActive, size: 40)
                    .opacity(device.isConnected ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary)
                            .lineLimit(1)
                        if !device.isEnabled { PillTag(text: "Off", color: Brand.textTertiary) }
                    }
                    Text(device.connectionLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textTertiary)
                        .lineLimit(1)
                        .help(device.identityDescription)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if device.hasSavedPosition && device.isConnected {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.accent.opacity(0.70))
                        .help("A saved cursor position exists for this device")
                }

                Toggle("", isOn: Binding(
                    get: { device.isEnabled },
                    set: { engine.setEnabled(deviceID: device.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Brand.accent)
                .controlSize(.mini)
                .disabled(!device.isConnected)
                .help(device.isEnabled ? "Disable this device" : "Enable this device")

                AssignmentMenu(engine: engine, device: device)

                deviceMenu
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .opacity(device.isConnected ? 1 : 0.72)
    }

    private var deviceMenu: some View {
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
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Activity

@MainActor
private final class ActivityFilterStore: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case switches = "Switches"
        case devices = "Devices"
        case system = "System"

        var id: String { rawValue }
    }

    @Published var filter: Filter = .all

    func matches(_ entry: DiagnosticEntry) -> Bool {
        switch filter {
        case .all:
            return true
        case .switches:
            return entry.category == "Switch"
        case .devices:
            return entry.category == "Devices" || entry.category == "Display"
        case .system:
            return !["Switch", "Devices", "Display"].contains(entry.category)
        }
    }
}

private struct ActivitySettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine
    @StateObject private var filters = ActivityFilterStore()

    private var entries: [DiagnosticEntry] {
        engine.log.entries.filter(filters.matches).suffix(250).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let lastSwitch = engine.lastSwitch {
                GlassCard(title: "Last switch", symbol: "arrow.left.arrow.right") {
                    HStack(spacing: 13) {
                        DeviceGlyph(symbol: "cursorarrow", active: true, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lastSwitch.deviceName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Brand.textPrimary)
                            Text(lastSwitch.at.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 11))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if lastSwitch.wasWarped {
                            PillTag(text: "Restored", color: Brand.accent)
                        }
                    }
                }
            }

            GlassCard(
                title: "Activity log",
                symbol: "waveform.path.ecg"
            ) {
                HStack(spacing: 6) {
                    ForEach(ActivityFilterStore.Filter.allCases) { filter in
                        FilterChip(
                            title: filter.rawValue,
                            selected: filters.filter == filter
                        ) {
                            filters.filter = filter
                        }
                    }
                    Spacer(minLength: 0)
                    Text("\(entries.count) entries")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textTertiary)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if entries.isEmpty {
                            Text("No activity recorded yet.")
                                .font(.system(size: 11))
                                .foregroundStyle(Brand.textTertiary)
                                .padding(10)
                        } else {
                            ForEach(entries) { entry in
                                LogLineView(entry: entry)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 300)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.26))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    Button("Clear") { engine.log.clear() }
                        .buttonStyle(GhostButtonStyle(compact: true))
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(engine.log.recentText(limit: 250), forType: .string)
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    Button("Reveal Log") {
                        NSWorkspace.shared.activateFileViewerSelecting([engine.log.fileURL])
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    Button("Saved State") {
                        model.revealStateFile()
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @StateObject private var hover = HoverStore()

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : Brand.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 25)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            selected
                                ? AnyShapeStyle(Brand.accent.opacity(0.30))
                                : AnyShapeStyle(Color.white.opacity(hover.isHovering ? 0.09 : 0.055))
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            selected ? Brand.accent.opacity(0.48) : Color.white.opacity(0.09),
                            lineWidth: 1
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hover.isHovering)
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Brand.accent.opacity(0.30))
                        .frame(width: 150, height: 150)
                        .blur(radius: 42)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                        .frame(width: 152, height: 152)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.045), lineWidth: 1)
                        .frame(width: 194, height: 194)
                    BrandIcon(size: 108, glow: true)
                }
                .frame(height: 200)

                VStack(spacing: 6) {
                    Text("DualPoint")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("One cursor for every device.")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    aboutLine("cursorarrow.rays", "Each device keeps its own position.")
                    aboutLine("display", "Assign devices to any display.")
                    aboutLine("lock.shield", "No keystrokes or network access.")
                    aboutLine("menubar.rectangle", "No Dock icon.")
                }
            }
            .frame(maxWidth: 470)

            VStack(spacing: 9) {
                Text("Version \(DualPointCore.version) · macOS 13 or later")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textTertiary)
                Text("Copyright © 2026 DualPoint. All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textTertiary)
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private func aboutLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Brand.accent.opacity(0.13))
                    .frame(width: 26, height: 26)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.accent)
            }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
