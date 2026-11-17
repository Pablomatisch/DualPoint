import SwiftUI
import DualPointCore

@MainActor
private final class OnboardingStepStore: ObservableObject {
    @Published private(set) var index: Int
    @Published private(set) var direction = 1

    init(index: Int = 0) {
        self.index = min(max(index, 0), 3)
    }

    func go(to newIndex: Int) {
        let target = min(max(newIndex, 0), 3)
        guard target != index else { return }
        direction = target > index ? 1 : -1
        index = target
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine
    let onFinish: () -> Void

    @StateObject private var stepStore: OnboardingStepStore

    init(
        model: AppModel,
        engine: DualPointEngine,
        initialStep: Int = 0,
        onFinish: @escaping () -> Void
    ) {
        self.model = model
        self.engine = engine
        self.onFinish = onFinish
        _stepStore = StateObject(wrappedValue: OnboardingStepStore(index: initialStep))
    }

    private var step: Int { stepStore.index }

    private let stepShortTitles = [
        "Welcome",
        "Permission",
        "Assignments",
        "Test drive"
    ]

    private var canFinish: Bool {
        engine.permissions.hidAccessGranted && engine.permissions.listenEventAccessGranted
    }

    var body: some View {
        ZStack {
            WindowBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                progressBar
                DividerLine()

                ScrollView {
                    ZStack(alignment: .topLeading) {
                        stepContent
                            .id(step)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(x: CGFloat(stepStore.direction) * 26)),
                                    removal: .opacity.combined(with: .offset(x: CGFloat(-stepStore.direction) * 22))
                                )
                            )
                    }
                    .animation(.spring(response: 0.40, dampingFraction: 0.88), value: step)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)

                DividerLine()
                footer
            }
        }
        .frame(minWidth: 740, minHeight: 700)
        .preferredColorScheme(.dark)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            BrandIcon(size: 38, glow: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("DualPoint Setup")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("Step \(step + 1) of 4 · \(stepShortTitles[step])")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 46)
        .padding(.bottom, 14)
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(
                        index <= step
                            ? AnyShapeStyle(Brand.accentGradient)
                            : AnyShapeStyle(Color.white.opacity(0.10))
                    )
                    .frame(height: 4)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(index == step ? 0.22 : 0), lineWidth: 1)
                    )
                    .shadow(color: index <= step ? Brand.accent.opacity(0.35) : .clear, radius: 6, y: 2)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 18)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionStep
        case 2: assignmentStep
        default: testStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomeMark()

            VStack(alignment: .leading, spacing: 8) {
                Text("Two devices.\nTwo places.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your trackpad and mouse each remember their own spot. Pick one up and the cursor returns to where you left it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                featureCard(
                    symbol: "cursorarrow.rays",
                    title: "Move both at once",
                    detail: "The first device keeps the real cursor; the other gets a blue one."
                )
                featureCard(
                    symbol: "display.2",
                    title: "Your layout",
                    detail: "Assign any device to a display."
                )
                featureCard(
                    symbol: "lock.shield",
                    title: "Private by design",
                    detail: "No keystrokes or network access."
                )
                featureCard(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Always remembered",
                    detail: "Saved across restarts and display changes."
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("Every setting stays available from the menu bar.")
                    .font(.system(size: 10))
            }
            .foregroundStyle(Brand.textTertiary)
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Brand.warning.opacity(0.22))
                        .frame(width: 82, height: 82)
                        .blur(radius: 22)
                    Circle()
                        .fill(Brand.warning.opacity(0.13))
                        .frame(width: 64, height: 64)
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("One required. One for two cursors.")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Input Monitoring lets DualPoint match pointer events to the physical device. Accessibility is optional: it lets a second device move the blue cursor independently while both are in use.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GlassCard(
                title: "What DualPoint sees",
                subtitle: "Only that a known device moved, clicked or scrolled.",
                symbol: "eye.slash.fill"
            ) {
                HStack(spacing: 10) {
                    privacyTile("No keystrokes", symbol: "keyboard")
                    privacyTile("No movement history", symbol: "point.topleft.down.curvedto.point.bottomright.up")
                    privacyTile("No network", symbol: "wifi.slash")
                }
            }

            GlassCard(
                title: "Permission status",
                subtitle: "Input Monitoring is required. Accessibility adds the second cursor.",
                symbol: "lock.shield.fill"
            ) {
                StatusRow(
                    title: "Input Monitoring",
                    detail: canFinish
                        ? "Granted."
                        : "Required to list and distinguish external pointing devices.",
                    isGood: canFinish
                )

                StatusRow(
                    title: "Pointer monitoring",
                    detail: engine.permissions.eventTapAvailable
                        ? "Running, listen-only."
                        : "Waiting for permission.",
                    isGood: engine.permissions.eventTapAvailable
                )

                StatusRow(
                    title: "Accessibility",
                    detail: engine.canSuppressPointerEvents
                        ? "Granted. The built-in trackpad can also drive the blue cursor."
                        : (engine.permissions.accessibilityTrusted
                            ? "Granted, but the pointer tap is listen-only. Restart DualPoint."
                            : "Optional. External devices use raw HID; this is only needed for the built-in trackpad."),
                    isGood: engine.canSuppressPointerEvents || engine.canIsolateExternalDevices
                )

                HStack(spacing: 8) {
                    Button("Grant Input Monitoring") {
                        engine.requestInputMonitoring()
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))

                    Button("Open Input Monitoring") {
                        engine.openInputMonitoringSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    Button("Check Again") {
                        engine.refreshPermissions()
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    Spacer(minLength: 0)
                }

                if !engine.canSuppressPointerEvents {
                    HStack(spacing: 8) {
                        Button("Enable Accessibility") {
                            engine.requestAccessibility()
                        }
                        .buttonStyle(SecondaryButtonStyle(compact: true))

                        Button("Open Accessibility Settings") {
                            engine.openAccessibilitySettings()
                        }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        Spacer(minLength: 0)
                    }
                }

                if !canFinish {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Brand.warning)
                            .font(.system(size: 11))
                        Text("If no prompt appears, enable DualPoint under Privacy & Security → Input Monitoring. You can continue; switching stays paused.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("Permissions are tied to the app signature, so rebuilding may require granting them again.")
                .font(.system(size: 10))
                .foregroundStyle(Brand.textTertiary)
        }
    }

    private var assignmentStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose a home for each device")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Assignments are a starting point. Once you use a device, its last position wins.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Use Recommended") {
                    engine.applyRecommendedSetup()
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(engine.connectedDevices.isEmpty)
            }

            if engine.connectedDevices.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("No devices are visible yet")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary)
                        Text(canFinish
                             ? "Connect a mouse or trackpad and it will appear here."
                             : "Grant Input Monitoring to list external devices. The built-in trackpad may already appear once permission is granted.")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !canFinish {
                            Button("Back to Permissions") { stepStore.go(to: 1) }
                                .buttonStyle(SecondaryButtonStyle(compact: true))
                        }
                    }
                }
            } else {
                VStack(spacing: 9) {
                    ForEach(engine.connectedDevices) { device in
                        HoverCard(active: device.isActive, cornerRadius: 15) {
                            HStack(spacing: 11) {
                                DeviceGlyph(symbol: device.kind.symbol, active: device.isActive, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Brand.textPrimary)
                                    Text(device.connectionLabel)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Brand.textTertiary)
                                }
                                Spacer(minLength: 8)
                                AssignmentMenu(engine: engine, device: device)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }

            GlassCard(
                title: "Detected displays",
                subtitle: "Updates automatically.",
                symbol: "display.2"
            ) {
                DisplayMap(
                    displays: engine.displays,
                    activeDisplayID: engine.activeDevice?.assignment.displayUUID
                )

                if !engine.displays.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(engine.displays) { display in
                            HStack(spacing: 6) {
                                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(display.isBuiltIn ? Brand.cyan : Brand.accent)
                                Text(display.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Brand.textSecondary)
                                    .lineLimit(1)
                                if display.isMain { PillTag(text: "Main") }
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 25)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.055)))
                            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassCard(
                title: "Try the handover",
                subtitle: engine.isSwitchingEnabled
                    ? "Move the trackpad, pause, then move the mouse."
                    : "Once permissions and displays are set, move each device to test the switch.",
                symbol: "cursorarrow.motionlines"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    instructionRow(number: "1", text: "Move the trackpad. The cursor goes to the MacBook display.")
                    instructionRow(number: "2", text: "Move the mouse. The cursor returns to its own display.")
                    instructionRow(number: "3", text: "Move both together. The first device keeps the real cursor; the other gets a blue one, then the real cursor follows once it stops.")
                }

                if engine.interimCursorEnabled && !engine.supportsInterimCursor {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Brand.accent)
                            .font(.system(size: 11))
                        Text("External devices are isolated through raw HID. Accessibility and an active pointer tap are only needed for the built-in trackpad fallback.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !engine.managedDevices.isEmpty && engine.isSwitchingEnabled {
                    DividerLine()
                    HStack(spacing: 8) {
                        ForEach(engine.managedDevices) { device in
                            Button("Move with \(device.name)") {
                                engine.activate(deviceID: device.id)
                            }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                        }
                        Spacer(minLength: 0)
                    }
                }

                DividerLine()

                Toggle(isOn: Binding(
                    get: { engine.automaticSwitching },
                    set: { engine.setAutomaticSwitching($0) }
                )) {
                    Text("Switch automatically")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Brand.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(Brand.accent)
            }

            if !canFinish {
                PermissionNotice(engine: engine)
            }
        }
        .onAppear { engine.setTestDriving(true) }
        .onDisappear { engine.setTestDriving(false) }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Set Up Later") {
                onFinish()
            }
            .buttonStyle(GhostButtonStyle())

            Spacer()

            Button("Back") {
                stepStore.go(to: step - 1)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(step == 0)

            if step < 3 {
                Button(step == 1 && !canFinish ? "Continue Anyway" : "Continue") {
                    stepStore.go(to: step + 1)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Finish Setup") {
                    engine.completeOnboarding()
                    onFinish()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 17)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Helpers

    private func featureCard(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Brand.accent.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.accent)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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

    private func privacyTile(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Brand.success)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Brand.accentGradient))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Welcome illustration

private struct WelcomeMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.accent.opacity(0.30))
                .frame(width: 160, height: 160)
                .blur(radius: 46)
            Circle()
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: 200, height: 200)
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.05),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 7])
                )
                .frame(width: 252, height: 252)

            BrandIcon(size: 86, glow: true)

            deviceChip(symbol: "rectangle.and.hand.point.up.left.fill", title: "Trackpad")
                .offset(x: -112, y: 30)
            deviceChip(symbol: "computermouse.fill", title: "Mouse")
                .offset(x: 110, y: -30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .clipped()
    }

    private func deviceChip(symbol: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Brand.accent)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.075)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)
    }
}
