import SwiftUI
import AppKit
import DualPointCore

// MARK: - Hover

@MainActor
final class HoverStore: ObservableObject {
    @Published var isHovering = false
}

struct HoverCard<Content: View>: View {
    var active: Bool
    var cornerRadius: CGFloat
    var inset: CGFloat
    @ViewBuilder var content: Content

    @StateObject private var hover = HoverStore()

    init(
        active: Bool = false,
        cornerRadius: CGFloat = 15,
        inset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.active = active
        self.cornerRadius = cornerRadius
        self.inset = inset
        self.content = content()
    }

    var body: some View {
        content
            .padding(inset)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(active ? 0.115 : (hover.isHovering ? 0.092 : 0.062)),
                                Color.white.opacity(active ? 0.055 : 0.028)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                active ? Brand.accent.opacity(0.58) : Color.white.opacity(hover.isHovering ? 0.20 : 0.10),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: active ? Brand.accent.opacity(0.20) : Color.black.opacity(hover.isHovering ? 0.20 : 0.08),
                radius: active ? 16 : 9,
                x: 0,
                y: 5
            )
            .scaleEffect(hover.isHovering ? 1.004 : 1)
            .animation(.easeOut(duration: 0.16), value: hover.isHovering)
            .onHover { hover.isHovering = $0 }
    }
}

// MARK: - Surfaces

struct PanelBackground: View {
    var cornerRadius: CGFloat = 22

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
            Brand.panelTint
            RadialGradient(
                colors: [Brand.accent.opacity(0.28), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 380
            )
            RadialGradient(
                colors: [Brand.violet.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 360
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.055), .white.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}

struct WindowBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.045, blue: 0.085).opacity(0.92),
                    Color(red: 0.018, green: 0.018, blue: 0.038).opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Brand.accent.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 720
            )
            RadialGradient(
                colors: [Brand.violet.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 640
            )
        }
    }
}

// MARK: - Cards

struct GlassCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    var symbol: String?
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if title != nil || subtitle != nil {
                HStack(alignment: .top, spacing: 12) {
                    if let symbol {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Brand.accent.opacity(0.14))
                                .frame(width: 32, height: 32)
                            Image(systemName: symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Brand.accent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        if let title {
                            Text(title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(Brand.textPrimary)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Brand.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Brand.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Brand.cardEdge, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 16, x: 0, y: 9)
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.12), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

// MARK: - Typography

struct SectionLabel: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Brand.textTertiary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Brand.textTertiary)
            }
        }
    }
}

struct ScreenHeader: View {
    var eyebrow: String? = nil
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(Brand.accent.opacity(0.85))
            }
            Text(title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.textPrimary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pills & tags

struct StatusPill: View {
    let text: String
    let color: Color
    var showsDot: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
                    .shadow(color: color.opacity(0.9), radius: 4)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(color.opacity(0.11)))
        .overlay(Capsule(style: .continuous).strokeBorder(color.opacity(0.24), lineWidth: 1))
        .fixedSize()
    }
}

struct PillTag: View {
    let text: String
    var color: Color = Brand.accent

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(color.opacity(0.13)))
    }
}

// MARK: - Live indicator

@MainActor
final class PulseStore: ObservableObject {
    @Published var expanded = false
}

struct PulseDot: View {
    var color: Color
    var size: CGFloat = 6

    @StateObject private var store = PulseStore()

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.28))
                .frame(width: size * 2.2, height: size * 2.2)
                .scaleEffect(store.expanded ? 1.85 : 0.75)
                .opacity(store.expanded ? 0 : 0.85)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.9), radius: 5)
        }
        .frame(width: size * 3.6, height: size * 3.6)
        .onAppear {
            store.expanded = false
            withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) {
                store.expanded = true
            }
        }
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, compact: compact)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: PrimaryButtonStyle.Configuration
    let compact: Bool

    @StateObject private var hover = HoverStore()

    var body: some View {
        let radius: CGFloat = compact ? 9 : 11
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 13 : 16)
            .frame(height: compact ? 30 : 35)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Brand.accentGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color.white.opacity(hover.isHovering ? 0.16 : 0))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(
                color: Brand.accent.opacity(hover.isHovering ? 0.55 : 0.30),
                radius: hover.isHovering ? 16 : 10,
                x: 0,
                y: 5
            )
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: hover.isHovering)
            .onHover { hover.isHovering = $0 }
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, compact: compact)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: SecondaryButtonStyle.Configuration
    let compact: Bool

    @StateObject private var hover = HoverStore()

    var body: some View {
        let radius: CGFloat = compact ? 9 : 11
        configuration.label
            .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, compact ? 12 : 15)
            .frame(height: compact ? 30 : 35)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(hover.isHovering ? 0.13 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(hover.isHovering ? 0.24 : 0.13), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: hover.isHovering)
            .onHover { hover.isHovering = $0 }
            .contentShape(Rectangle())
    }
}

struct GhostButtonStyle: ButtonStyle {
    var compact: Bool = false
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration, compact: compact, destructive: destructive)
    }
}

private struct GhostButtonBody: View {
    let configuration: GhostButtonStyle.Configuration
    let compact: Bool
    let destructive: Bool

    @StateObject private var hover = HoverStore()

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .medium))
            .foregroundStyle(
                destructive
                    ? Brand.danger.opacity(hover.isHovering ? 1 : 0.82)
                    : (hover.isHovering ? Brand.textPrimary : Brand.textSecondary)
            )
            .padding(.horizontal, compact ? 8 : 10)
            .frame(height: compact ? 28 : 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hover.isHovering ? 0.07 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: hover.isHovering)
            .onHover { hover.isHovering = $0 }
            .contentShape(Rectangle())
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        GlassIconButtonBody(configuration: configuration, size: size)
    }
}

private struct GlassIconButtonBody: View {
    let configuration: GlassIconButtonStyle.Configuration
    let size: CGFloat

    @StateObject private var hover = HoverStore()

    var body: some View {
        configuration.label
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(hover.isHovering ? Brand.textPrimary : Brand.textSecondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Color.white.opacity(hover.isHovering ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(Color.white.opacity(hover.isHovering ? 0.20 : 0.10), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: hover.isHovering)
            .onHover { hover.isHovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

// MARK: - Device glyph

struct DeviceGlyph: View {
    let symbol: String
    var active: Bool = false
    var size: CGFloat = 36

    var body: some View {
        let radius = size * 0.30
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: active
                            ? [Brand.accent.opacity(0.44), Brand.violet.opacity(0.22)]
                            : [Color.white.opacity(0.10), Color.white.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(active ? Color.white : Brand.textSecondary)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(active ? Brand.accent.opacity(0.58) : Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: active ? Brand.accent.opacity(0.35) : .clear, radius: 10, x: 0, y: 4)
    }
}

// MARK: - Assignment menu

struct AssignmentMenu: View {
    @ObservedObject var engine: DualPointEngine
    let device: PointingDevice

    var body: some View {
        Menu {
            ForEach(engine.displays) { display in
                Button {
                    engine.assign(deviceID: device.id, to: display)
                } label: {
                    if device.assignment.displayUUID == display.id {
                        Label(display.name, systemImage: "checkmark")
                    } else {
                        Text(display.name)
                    }
                }
            }

            if let name = device.assignment.displayName,
               !device.assignment.isUnmanaged,
               !engine.displays.contains(where: { $0.id == device.assignment.displayUUID }) {
                Divider()
                Text("\(name) is disconnected")
            }

            Divider()
            Button {
                engine.assign(deviceID: device.id, to: nil)
            } label: {
                if device.assignment.isUnmanaged {
                    Label("Unmanaged", systemImage: "checkmark")
                } else {
                    Text("Unmanaged")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "display")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(device.assignment.isUnmanaged ? Brand.textTertiary : Brand.accent)
                Text(device.assignmentDescription)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .foregroundStyle(device.assignment.isUnmanaged ? Brand.textTertiary : Brand.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.065)))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!device.isConnected)
        .help("Choose which display this device belongs to")
    }
}

// MARK: - Status

struct StatusRow: View {
    let title: String
    let detail: String?
    let isGood: Bool
    var symbol: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            let color = isGood ? Brand.success : Brand.warning
            ZStack {
                Circle()
                    .fill(color.opacity(0.13))
                    .frame(width: 27, height: 27)
                Image(systemName: symbol ?? (isGood ? "checkmark" : "exclamationmark"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 6)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
        }
    }
}

// MARK: - Permission banner

struct PermissionNotice: View {
    @ObservedObject var engine: DualPointEngine
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(Brand.warning.opacity(0.16))
                        .frame(width: 28, height: 28)
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Input Monitoring is required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                    if !compact {
                        Text("DualPoint identifies which device moved. It never records keystrokes or movement history.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Brand.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button("Grant Permission") {
                    engine.requestInputMonitoring()
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))

                Button("Check Again") {
                    engine.refreshPermissions()
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))

                if !compact {
                    Button("Open Settings") {
                        engine.openInputMonitoringSettings()
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Brand.warning.opacity(0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.24), lineWidth: 1)
        )
    }
}

// MARK: - Display map

struct DisplayMap: View {
    let displays: [DisplayInfo]
    var activeDisplayID: String?
    var height: CGFloat = 132

    var body: some View {
        GeometryReader { geometry in
            let content = layout(in: geometry.size)
            ZStack(alignment: .topLeading) {
                if displays.isEmpty {
                    Text("No active displays")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Brand.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(displays) { display in
                        if let frame = content.frames[display.id] {
                            displayTile(display, frame: frame)
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func displayTile(_ display: DisplayInfo, frame: CGRect) -> some View {
        let isActive = activeDisplayID == display.id
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isActive
                            ? [Brand.accent.opacity(0.35), Brand.violet.opacity(0.20)]
                            : [Color.white.opacity(0.085), Color.white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isActive ? Brand.accent.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: isActive ? Brand.accent.opacity(0.28) : .clear, radius: 10, y: 4)

            VStack(spacing: 3) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? .white : Brand.textSecondary)
                if frame.width > 76 {
                    Text(display.name)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isActive ? .white : Brand.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                if frame.height > 50 {
                    Text(display.detailLabel)
                        .font(.system(size: 7))
                        .foregroundStyle(isActive ? Color.white.opacity(0.8) : Brand.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }

    private func layout(in size: CGSize) -> (frames: [String: CGRect], scale: CGFloat) {
        guard !displays.isEmpty else { return ([:], 1) }
        var union = CGRect.null
        for display in displays {
            union = union.union(display.bounds)
        }
        let padding: CGFloat = 14
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        let scale = min(availableWidth / max(union.width, 1), availableHeight / max(union.height, 1))
        let offsetX = (size.width - union.width * scale) / 2
        let offsetY = (size.height - union.height * scale) / 2
        var frames: [String: CGRect] = [:]
        for display in displays {
            let width = display.bounds.width * scale
            let height = display.bounds.height * scale
            let x = (display.bounds.minX - union.minX) * scale + offsetX
            let y = (union.maxY - display.bounds.maxY) * scale + offsetY
            frames[display.id] = CGRect(x: x, y: y, width: width, height: height)
        }
        return (frames, scale)
    }
}

// MARK: - Log rows

struct LogLineView: View {
    let entry: DiagnosticEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .foregroundStyle(Brand.textTertiary)
                .frame(width: 68, alignment: .leading)
            Text(entry.category)
                .foregroundStyle(color)
                .frame(width: 72, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 9.5, design: .monospaced))
        .textSelection(.enabled)
    }

    private var color: Color {
        switch entry.category {
        case "Switch": return Brand.accent
        case "Devices": return Brand.cyan
        case "Display": return Brand.violet
        case "Permission": return Brand.warning
        default: return Brand.textSecondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
