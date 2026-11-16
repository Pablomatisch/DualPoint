import SwiftUI
import AppKit
import DualPointCore

/// The shared visual language for DualPoint.
///
/// The design is intentionally dark, quiet and translucent: a single accent
/// gradient against layered glass surfaces, generous rounding and restrained
/// motion. Every surface is built from the tokens here so the menu bar panel,
/// Settings and Setup feel like one product.
enum Brand {
    // Accent family
    static let accent = Color(red: 0.46, green: 0.44, blue: 1.00)
    static let violet = Color(red: 0.66, green: 0.40, blue: 1.00)
    static let cyan = Color(red: 0.24, green: 0.80, blue: 1.00)
    static let pink = Color(red: 1.00, green: 0.42, blue: 0.72)

    // Semantic colors
    static let success = Color(red: 0.24, green: 0.90, blue: 0.66)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.28)
    static let danger = Color(red: 1.00, green: 0.40, blue: 0.50)

    // Text
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.36)

    // Surfaces
    static let surface = Color.white.opacity(0.06)
    static let surfaceHover = Color.white.opacity(0.10)
    static let stroke = Color.white.opacity(0.10)
    static let strokeStrong = Color.white.opacity(0.20)

    // Gradients
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.50, green: 0.45, blue: 1.00), Color(red: 0.71, green: 0.37, blue: 0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGlowGradient: LinearGradient {
        LinearGradient(
            colors: [accent, violet],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.075), Color.white.opacity(0.032)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardEdge: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.22), Color.white.opacity(0.055), Color.white.opacity(0.09)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var panelTint: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.055, green: 0.055, blue: 0.105).opacity(0.78),
                Color(red: 0.025, green: 0.025, blue: 0.055).opacity(0.88)
            ],
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

// MARK: - Brand mark

struct BrandIcon: View {
    var size: CGFloat = 36
    var cornerRadius: CGFloat? = nil
    var glow: Bool = false

    var body: some View {
        let radius = cornerRadius ?? size * 0.27
        Group {
            if let image = Brand.iconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Brand.accentGradient)
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Brand.accent.opacity(glow ? 0.55 : 0.22), radius: glow ? size * 0.42 : size * 0.12, x: 0, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

// MARK: - Native vibrancy

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = emphasized
    }
}

// MARK: - Device metadata

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
        if !isConnected || !isEnabled || assignment.isUnmanaged { return Brand.textTertiary }
        return Brand.accent
    }
}

extension DualPointEngine {
    var statusColor: Color {
        if !hasCompletedOnboarding { return Brand.warning }
        if !permissions.isReadyForAutomaticSwitching { return Brand.warning }
        if !automaticSwitching { return Brand.textTertiary }
        if managedDevices.isEmpty { return Brand.warning }
        if isSwitchingEnabled { return Brand.success }
        return Brand.warning
    }
}
