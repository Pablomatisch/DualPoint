import SwiftUI
import AppKit
import DualPointCore

enum Brand {
    static let accent = Color(red: 0.27, green: 0.47, blue: 0.98)
    static let accentDeep = Color(red: 0.47, green: 0.29, blue: 0.93)
    static let success = Color(red: 0.20, green: 0.68, blue: 0.42)
    static let warning = Color(red: 0.93, green: 0.61, blue: 0.16)

    static var gradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var softGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.16), accentDeep.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let iconImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

struct BrandIcon: View {
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Group {
            if let image = Brand.iconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(Brand.gradient)
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
        .fixedSize()
    }
}

struct SettingsCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

struct StatusRow: View {
    let title: String
    let detail: String?
    let isGood: Bool
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGood ? Brand.success : Brand.warning)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }
}

extension DeviceKind {
    var symbol: String {
        switch self {
        case .builtInTrackpad, .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .mouse: return "computermouse.fill"
        case .other: return "cursorarrow"
        }
    }
}

extension PointingDevice {
    var statusColor: Color {
        if !isConnected { return .secondary }
        if !isEnabled { return .secondary }
        if assignment.isUnmanaged { return .secondary }
        return Brand.accent
    }
}

extension DualPointEngine {
    var statusColor: Color {
        if !hasCompletedOnboarding { return Brand.warning }
        if !permissions.isReadyForAutomaticSwitching { return Brand.warning }
        if !automaticSwitching { return .secondary }
        if managedDevices.isEmpty { return Brand.warning }
        if isSwitchingEnabled { return Brand.success }
        return Brand.warning
    }
}

struct AssignmentMenu: View {
    @ObservedObject var engine: DualPointEngine
    let device: PointingDevice
    var compact: Bool = false

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
            HStack(spacing: 4) {
                Text(device.assignmentDescription)
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(device.assignment.isUnmanaged ? .secondary : .primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!device.isConnected)
        .help("Choose which display this device belongs to")
    }
}

struct ActiveDeviceCard: View {
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Brand.softGradient)
                    .frame(width: 38, height: 38)
                Image(systemName: engine.activeDevice?.kind.symbol ?? "cursorarrow")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.activeDevice?.name ?? "No device used yet")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(engine.activeDevice?.assignmentDescription ?? "Use any pointing device to begin")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let lastSwitch = engine.lastSwitch, lastSwitch.wasWarped {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .help("Cursor was restored for this switch")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Brand.softGradient)
        )
    }
}

struct PermissionNotice: View {
    @ObservedObject var engine: DualPointEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Brand.warning)
                Text("Input Monitoring permission is required")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("DualPoint needs permission to identify which device moved. It never records keystrokes or movement history.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Grant Permission") {
                    engine.requestInputMonitoring()
                }
                .controlSize(.small)
                Button("Open System Settings") {
                    engine.openInputMonitoringSettings()
                }
                .controlSize(.small)
                Button("Check Again") {
                    engine.refreshPermissions()
                }
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Brand.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.25))
        )
    }
}
