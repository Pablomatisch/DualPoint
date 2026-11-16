import AppKit
import SwiftUI
import QuartzCore
import DualPointCore

enum PanelMetrics {
    static let contentWidth: CGFloat = 400
    static let contentHeight: CGFloat = 404
    static let cornerRadius: CGFloat = 22
    /// The shadow needs room on the sides and bottom. The top stays tight so
    /// the panel never covers the menu bar item that opened it.
    static let sideInset: CGFloat = 24
    static let bottomInset: CGFloat = 24
    static let topInset: CGFloat = 8

    static var panelSize: NSSize {
        NSSize(
            width: contentWidth + sideInset * 2,
            height: contentHeight + topInset + bottomInset
        )
    }
}

@MainActor
final class PanelPresentation: ObservableObject {
    @Published var isVisible = false
}

/// Owns the custom menu bar item and the immersive translucent panel.
///
/// `MenuBarExtra` cannot provide the full-bleed glass, custom shadow and
/// spring entrance used by the design, so the panel is a borderless
/// `NSPanel` hosting the same SwiftUI content. It never activates DualPoint:
/// the panel can become key, buttons work, and the rest of the system keeps
/// focus.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var panel: DualPointPanel?
    private let presentation = PanelPresentation()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isVisible = false

    private override init() {
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "cursorarrow.rays",
                accessibilityDescription: "DualPoint"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "DualPoint"
            button.setAccessibilityLabel("DualPoint")
        }
        statusItem = item

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Show / hide

    @objc private func togglePanel() {
        if isVisible {
            // A display change, Mission Control or the system can order the
            // window out without our knowledge. If that happened, resync and
            // open instead of hiding a panel the user cannot see.
            if panel?.isVisible == true, (panel?.alphaValue ?? 0) > 0.01 {
                hide()
                return
            }
            resetVisibility()
        }
        show()
    }

    @objc private func screensChanged() {
        guard isVisible,
              let panel,
              let button = statusItem?.button,
              let window = button.window else { return }
        position(panel, relativeTo: button, in: window)
    }

    private func resetVisibility() {
        removeEventMonitors()
        isVisible = false
        presentation.isVisible = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    func show() {
        if isVisible, let panel {
            guard panel.isVisible else {
                resetVisibility()
                show()
                return
            }
            return
        }
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        let panel = makePanelIfNeeded()

        position(panel, relativeTo: button, in: buttonWindow)
        presentation.isVisible = false
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        installEventMonitors()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                self.presentation.isVisible = true
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        removeEventMonitors()

        withAnimation(.easeIn(duration: 0.12)) {
            presentation.isVisible = false
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isVisible, let panel = self.panel else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        })
    }

    // MARK: - Panel construction

    private func makePanelIfNeeded() -> DualPointPanel {
        if let panel { return panel }

        let root = MenuBarPanelView(
            model: AppModel.shared,
            engine: AppModel.shared.engine,
            presentation: presentation
        )
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true

        let panel = DualPointPanel(
            contentRect: NSRect(origin: .zero, size: PanelMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.acceptsMouseMovedEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, relativeTo button: NSStatusBarButton, in window: NSWindow) {
        let buttonRect = button.convert(button.bounds, to: nil)
        let anchor = window.convertToScreen(buttonRect)
        let anchorPoint = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let size = PanelMetrics.panelSize
        var x = anchor.midX - size.width / 2
        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)

        // The glass itself starts a few points below the menu bar; the
        // transparent inset around it exists only to let the shadow render.
        let glassTop = anchor.minY - 9
        let panelTop = glassTop + PanelMetrics.topInset
        var y = panelTop - size.height
        if y < visibleFrame.minY + 8 {
            y = visibleFrame.minY + 8
        }

        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: false
        )
    }

    // MARK: - Dismissal

    private func installEventMonitors() {
        removeEventMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Clicking the menu bar item itself toggles the panel through
                // its action; do not pre-hide it here or the toggle would
                // immediately reopen it.
                if self.isMouseOverStatusItem { return }
                self.hide()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.hide()
            return nil
        }
    }

    private func removeEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private var isMouseOverStatusItem: Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return rect.contains(NSEvent.mouseLocation)
    }
}

private final class DualPointPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct MenuBarPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: DualPointEngine
    @ObservedObject var presentation: PanelPresentation

    var body: some View {
        MenuBarContentView(model: model, engine: engine)
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.60), radius: 26, x: 0, y: 16)
            .scaleEffect(presentation.isVisible ? 1 : 0.955, anchor: .top)
            .offset(y: presentation.isVisible ? 0 : -7)
            .opacity(presentation.isVisible ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: presentation.isVisible)
            .padding(.horizontal, PanelMetrics.sideInset)
            .padding(.top, PanelMetrics.topInset)
            .padding(.bottom, PanelMetrics.bottomInset)
            .frame(width: PanelMetrics.panelSize.width, height: PanelMetrics.panelSize.height)
    }
}
