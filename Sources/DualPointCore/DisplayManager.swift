import Foundation
import CoreGraphics
import AppKit

/// Enumerates connected displays in CoreGraphics global coordinates and keeps
/// the list current across reconfiguration, sleep/wake and screen changes.
@MainActor
public final class DisplayManager {
    public var onChange: (([DisplayInfo]) -> Void)?

    public private(set) var displays: [DisplayInfo] = []

    private var callbackInstalled = false
    private var observers: [NSObjectProtocol] = []
    private var refreshWorkItem: DispatchWorkItem?

    public init() {}

    public func start() {
        guard !callbackInstalled else { return }
        callbackInstalled = true

        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, context)

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })

        refresh()
    }

    public func stop() {
        guard callbackInstalled else { return }
        callbackInstalled = false
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, context)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
    }

    public func refresh() {
        let newDisplays = Self.enumerate()
        if newDisplays != displays {
            displays = newDisplays
            onChange?(newDisplays)
        }
    }

    fileprivate func displayConfigurationChanged() {
        // Display changes arrive in bursts (begin/set/end). Coalesce them.
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    public static func enumerate() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        let screens = NSScreen.screens
        var result: [DisplayInfo] = []
        for id in ids.prefix(Int(count)) {
            let bounds = CGDisplayBounds(id)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            let screen = screens.first { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }

            let uuid: String
            if let rawUUID = CGDisplayCreateUUIDFromDisplayID(id) {
                uuid = CFUUIDCreateString(nil, rawUUID.takeRetainedValue()) as String
            } else {
                uuid = "display-\(id)"
            }

            let name = screen?.localizedName ?? "Display \(id)"
            let scale = Double(screen?.backingScaleFactor ?? 1)
            let pixelWidth = CGDisplayPixelsWide(id)
            let pixelHeight = CGDisplayPixelsHigh(id)

            result.append(DisplayInfo(
                id: uuid,
                displayID: id,
                name: name,
                bounds: bounds,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                pointWidth: Int(bounds.width.rounded()),
                pointHeight: Int(bounds.height.rounded()),
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scale: scale
            ))
        }

        return result.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            if lhs.bounds.minX != rhs.bounds.minX { return lhs.bounds.minX < rhs.bounds.minX }
            return lhs.bounds.minY < rhs.bounds.minY
        }
    }
}

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, _, context in
    guard let context else { return }
    let manager = Unmanaged<DisplayManager>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            manager.displayConfigurationChanged()
        }
    }
}
