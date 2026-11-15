import SwiftUI
import DualPointCore

@MainActor
private final class OnboardingStepStore: ObservableObject {
    @Published var index = 0
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine
    let onFinish: () -> Void

    @StateObject private var stepStore = OnboardingStepStore()

    private var step: Int {
        get { stepStore.index }
        nonmutating set { stepStore.index = newValue }
    }

    private let stepTitles = [
        "Welcome to DualPoint",
        "Allow Input Monitoring",
        "Choose where devices live",
        "Try it out"
    ]

    private let stepSubtitles = [
        "Give every physical pointing device its own cursor position.",
        "DualPoint needs permission to tell your devices apart.",
        "Assign the built-in trackpad and external devices to displays.",
        "Move each device and watch the cursor return to its own place."
    ]

    private var canFinish: Bool {
        engine.permissions.hidAccessGranted && engine.permissions.listenEventAccessGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0: welcomeStep
                    case 1: permissionStep
                    case 2: assignmentStep
                    default: testStep
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                BrandIcon(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stepTitles[step])
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(stepSubtitles[step])
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Brand.accent : (index < step ? Brand.accent.opacity(0.45) : Color.primary.opacity(0.12)))
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Brand.softGradient)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your trackpad and mouse remember different places.")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            Text("Use the built-in trackpad and the pointer returns to the MacBook display. Pick up the external mouse and it jumps back to its own last position on the external monitor.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                featureRow(
                    symbol: "cursorarrow.rays",
                    title: "One real cursor",
                    detail: "No second cursor, no display boundaries, no changes to dragging or gestures."
                )
                featureRow(
                    symbol: "display.2",
                    title: "Your displays, your layout",
                    detail: "Assign the built-in display, any external display, or leave a device unmanaged."
                )
                featureRow(
                    symbol: "lock.shield",
                    title: "Private by design",
                    detail: "DualPoint identifies devices locally. It never records keystrokes, movement history or sends data anywhere."
                )
                featureRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Remembered across restarts",
                    detail: "Positions are saved as display-relative anchors, so they survive restarts and resolution changes."
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("You can change every setting later from the menu bar.")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.tertiary)
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: "Why Input Monitoring?",
                subtitle: "macOS does not label pointer events with a device, so DualPoint correlates system pointer events with the physical device that produced them."
            ) {
                Text("DualPoint never captures the content of your input, only the fact that a known device produced a movement, click or scroll.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "Permission status") {
                StatusRow(
                    title: "Input Monitoring",
                    detail: engine.permissions.hidAccessGranted && engine.permissions.listenEventAccessGranted
                        ? "Granted. External devices are visible."
                        : "Required to list and distinguish external pointing devices.",
                    isGood: engine.permissions.hidAccessGranted && engine.permissions.listenEventAccessGranted
                )

                StatusRow(
                    title: "Pointer event monitoring",
                    detail: engine.permissions.eventTapAvailable
                        ? "Running. The tap is listen-only and never modifies events."
                        : "Waiting for permission.",
                    isGood: engine.permissions.eventTapAvailable
                )

                HStack(spacing: 8) {
                    Button("Grant Input Monitoring") {
                        engine.requestInputMonitoring()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open System Settings") {
                        engine.openInputMonitoringSettings()
                    }

                    Button("Check Again") {
                        engine.refreshPermissions()
                    }
                }
                .controlSize(.small)

                if !canFinish {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Brand.warning)
                            .font(.system(size: 11))
                        Text("If macOS does not show the prompt, open System Settings → Privacy & Security → Input Monitoring and enable DualPoint. You can continue setup now; switching stays paused until permission is granted.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Brand.success)
                        Text("Permission granted. External devices can now be identified.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Permission is tied to the app signature. Rebuilding an ad-hoc signed build can require granting it again.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var assignmentStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Connected devices")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button("Use Recommended Setup") {
                    engine.applyRecommendedSetup()
                }
                .controlSize(.small)
                .disabled(engine.connectedDevices.isEmpty)
            }

            if engine.connectedDevices.isEmpty {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No devices are visible yet")
                            .font(.system(size: 12, weight: .semibold))
                        Text(canFinish
                             ? "Connect a mouse or trackpad and it will appear here."
                             : "Grant Input Monitoring to list external devices. The built-in trackpad may already appear once permission is granted.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !canFinish {
                            Button("Back to Permissions") { step = 1 }
                                .controlSize(.small)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(engine.connectedDevices) { device in
                        HStack(spacing: 11) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Brand.accent.opacity(0.12))
                                    .frame(width: 34, height: 34)
                                Image(systemName: device.kind.symbol)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Brand.accent)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(device.connectionLabel)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            AssignmentMenu(engine: engine, device: device)
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.07))
                        )
                    }
                }
            }

            SettingsCard(
                title: "Detected displays",
                subtitle: "Assignments are starting points. Once you use a device, its actual last position wins."
            ) {
                ForEach(engine.displays) { display in
                    HStack(spacing: 9) {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                            .foregroundStyle(Brand.accent)
                            .frame(width: 18)
                        Text(display.name)
                            .font(.system(size: 12, weight: .medium))
                        if display.isMain {
                            Text("MAIN")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Brand.accent)
                        }
                        if display.isBuiltIn {
                            Text("BUILT-IN")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Brand.accent)
                        }
                        Spacer()
                        Text(display.detailLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Current status") {
                StatusRow(
                    title: "Input Monitoring",
                    detail: canFinish ? "Granted" : "Missing — switching will stay paused",
                    isGood: canFinish
                )
                StatusRow(
                    title: "Pointer monitoring",
                    detail: engine.isMonitoring ? "Running" : "Not running",
                    isGood: engine.isMonitoring
                )

                Toggle(isOn: Binding(
                    get: { engine.automaticSwitching },
                    set: { engine.setAutomaticSwitching($0) }
                )) {
                    Text("Automatic switching")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
            }

            SettingsCard(
                title: "Try it now",
                subtitle: engine.isSwitchingEnabled
                    ? "Move the built-in trackpad, pause, then move the external mouse. Each device should return to its own position."
                    : "After finishing setup and granting permission, move each device to test the switch."
            ) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Brand.softGradient)
                            .frame(width: 42, height: 42)
                        Image(systemName: engine.activeDevice?.kind.symbol ?? "cursorarrow")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Brand.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.activeDevice?.name ?? "Waiting for input")
                            .font(.system(size: 13, weight: .semibold))
                        if let lastSwitch = engine.lastSwitch {
                            Text("Last switch: \(lastSwitch.deviceName)\(lastSwitch.wasWarped ? " · cursor restored" : "")")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Use any pointing device")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    StatusPill(text: engine.isSwitchingEnabled ? "Ready" : "Paused", color: engine.statusColor)
                }

                if !engine.managedDevices.isEmpty && engine.isSwitchingEnabled {
                    HStack(spacing: 8) {
                        ForEach(engine.managedDevices) { device in
                            Button("Move with \(device.name)") {
                                engine.activate(deviceID: device.id)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            if !canFinish {
                PermissionNotice(engine: engine)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.accent)
                Text("You can revisit this assistant any time from the menu bar.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Set Up Later") {
                onFinish()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button("Back") {
                step = max(0, step - 1)
            }
            .disabled(step == 0)

            if step < 3 {
                Button(step == 1 && !canFinish ? "Continue Anyway" : "Continue") {
                    step = min(3, step + 1)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Finish Setup") {
                    engine.completeOnboarding()
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func featureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Brand.accent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
