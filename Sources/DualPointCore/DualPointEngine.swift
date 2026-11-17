import Foundation
import Combine
import CoreGraphics
import AppKit

/// The coordinator that turns physical device activity into per-device cursor
/// positions.
///
/// A device "activates" when it sends movement, a button press or a real scroll.
/// On activation DualPoint saves the previous device's last cursor position and
/// restores the new device's position (or its assigned display on first use).
///
/// Only one *real* system cursor exists. When two devices move at the same time,
/// the one that owns the real cursor keeps it and a seizable external device
/// gets an app-drawn blue interim cursor. The blue device is seized through raw
/// HID so it cannot steer the real cursor at all. When it settles, the real
/// cursor is warped to its position and the blue pointer disappears.
///
/// The built-in trackpad cannot be seized through public APIs and consuming its
/// CGEvent in a tap would not stop the window server from moving the real
/// cursor, so it can never be the blue pointer. It always owns the real cursor
/// while a second external device is active.
@MainActor
public final class DualPointEngine: ObservableObject {
    public let store: StateStore
    public let log: DiagnosticLog

    @Published public private(set) var devices: [PointingDevice] = []
    @Published public private(set) var displays: [DisplayInfo] = []
    @Published public private(set) var activeDeviceID: String?
    @Published public private(set) var interimDeviceID: String?
    @Published public private(set) var permissions = PermissionSnapshot()
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var eventTapFailure: String?
    @Published public private(set) var lastSwitch: SwitchRecord?
    @Published public private(set) var builtInTrackpadAvailable = false
    @Published public private(set) var isRunning = false
    @Published public private(set) var automaticSwitching: Bool
    @Published public private(set) var hasCompletedOnboarding: Bool
    @Published public private(set) var isTestDriving = false
    @Published public private(set) var interimCursorEnabled: Bool
    @Published public private(set) var handoverCooldown: TimeInterval
    @Published public private(set) var lastErrorMessage: String?

    /// The app layer draws the interim cursor. It is intentionally not a
    /// published property so a moving ghost does not invalidate SwiftUI views.
    public var onInterimCursorChange: ((InterimCursor?) -> Void)?

    private let displayManager = DisplayManager()
    private let hidMonitor = HIDMonitor()
    private let eventTap = EventTapMonitor()

    private var activityTable = ActivityTable()
    private var connectedHID: [String: HIDDeviceInfo] = [:]
    private var cachedActiveAnchor: CursorAnchor?
    private var lastAnchorPersist: UInt64 = 0
    private var lastHIDMovementAt: UInt64 = 0
    private var anchorCaptureFloor: UInt64 = 0
    private var switchCandidateID: String?
    private var switchCandidateCount = 0
    private var switchCandidateAt: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var permissionTimerIsRunning = false
    private var lastLoggedPermissionKey = ""
    private var lastLoggedEventTapFailure: String?
    private var started = false

    private var arbiter: InterimCursorArbiter
    private var interimPoint: CGPoint?
    /// State for a drag started with the blue pointer. Synthetic mouse events
    /// temporarily move the real cursor, so every one of them restores this
    /// pre-click position belonging to the main device.
    private var interimButtonDown = false
    private var interimDragStartPoint: CGPoint?
    private var interimIsDragging = false
    /// True while the blue device is exclusively seized through raw HID.
    /// Its movement then arrives from SecondaryPointerMonitor, not from the tap.
    private var interimIsSeized = false
    /// Stable device key currently seized by the secondary monitor. Its HID
    /// reports must not be used for CGEvent attribution: the device cannot
    /// produce pointer events while seized, so a stale report would otherwise
    /// "explain" the trackpad's events and move the wrong pointer.
    private var seizedHIDKey: String?
    private var interimTimer: Timer?

    /// No new blue cursor may start immediately after a handover.
    private var interimRefractoryUntil: UInt64 = 0
    private var lastAutomaticSwitchAt: UInt64 = 0
    private var unmatchedStreak = 0
    private var lastUnmatchedAt: UInt64 = 0

    public init(store: StateStore? = nil, log: DiagnosticLog? = nil) {
        let resolvedStore = store ?? StateStore()
        self.store = resolvedStore
        self.log = log ?? DiagnosticLog()
        let policy = InterimCursorPolicy(
            isEnabled: resolvedStore.state.interimCursorEnabled,
            handoverCooldown: resolvedStore.state.handoverCooldown
        )
        self.automaticSwitching = resolvedStore.state.automaticSwitching
        self.hasCompletedOnboarding = resolvedStore.state.onboardingCompleted
        self.interimCursorEnabled = policy.isEnabled
        self.handoverCooldown = policy.handoverCooldown
        self.arbiter = InterimCursorArbiter(policy: policy)
        configureCallbacks()
    }

    // MARK: - Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        isRunning = true

        builtInTrackpadAvailable = BuiltInTrackpadDetector.hasBuiltInTrackpad()
        displayManager.start()
        displays = displayManager.displays
        rebuildDevices()
        installObservers()

        log.info("Engine", "DualPoint \(DualPointCore.version) starting")
        log.info("Display", displays.map { "\($0.name) \($0.bounds)" }.joined(separator: "; "))
        if builtInTrackpadAvailable {
            log.info("Devices", "Built-in trackpad detected")
        }

        refreshPermissionsAndMonitoring()
        if !isSwitchingEnabled {
            log.info("Engine", "Automatic switching paused until setup and permissions are complete")
        }
    }

    public func stop() {
        guard started else { return }
        persistActiveAnchor(force: true)
        hideInterimCursor(persist: true)
        started = false
        isRunning = false
        isTestDriving = false
        stopPermissionTimer()
        removeObservers()

        eventTap.stop()
        hidMonitor.stop()
        displayManager.stop()

        connectedHID.removeAll()
        activityTable.clear()
        cachedActiveAnchor = nil
        arbiter.reset()
        interimRefractoryUntil = 0
        lastAutomaticSwitchAt = 0
        interimIsSeized = false
        seizedHIDKey = nil
        interimDeviceID = nil
        resetInterimInputState()
        clearSwitchCandidate()
        isMonitoring = false
        rebuildDevices()
        store.flush()
        log.info("Engine", "Stopped")
    }

    public func quit() {
        stop()
        NSApp.terminate(nil)
    }

    // MARK: - Status

    /// True only when every prerequisite for an automatic cursor move is met.
    public var isSwitchingEnabled: Bool {
        isRunning
            && automaticSwitching
            && (hasCompletedOnboarding || isTestDriving)
            && permissions.isReadyForAutomaticSwitching
            && isMonitoring
    }

    public var activeDevice: PointingDevice? {
        guard let activeDeviceID else { return nil }
        return devices.first { $0.id == activeDeviceID }
    }

    public var interimDevice: PointingDevice? {
        guard let interimDeviceID else { return nil }
        return devices.first { $0.id == interimDeviceID }
    }

    /// Accessibility plus an active event tap. Consuming an event hides it from
    /// apps but does not stop the window server from moving the real cursor, so
    /// this cannot isolate a second pointer. It is reported for diagnostics and
    /// for the regular per-device switching path only.
    public var canSuppressPointerEvents: Bool {
        permissions.accessibilityTrusted && eventTap.canSuppressEvents
    }

    /// An external device can be seized through raw HID. The built-in trackpad
    /// cannot be isolated, so it can never own the blue pointer.
    public var canIsolateExternalDevices: Bool {
        hidMonitor.canSeizeDevices
    }

    /// Only an external device that can be seized can own the blue pointer.
    /// Consuming a `mouseMoved` event in a CGEventTap hides it from apps but
    /// does NOT stop the window server from moving the real cursor, so an
    /// unseizable device (the built-in trackpad) would move both pointers.
    public var supportsInterimCursor: Bool {
        interimCursorEnabled && canIsolateExternalDevices
    }

    private var canUseInterimCursor: Bool {
        isSwitchingEnabled && supportsInterimCursor
    }

    /// Set `defaults write com.dualpoint.DualPoint DualPointVerboseRouting -bool YES`
    /// to record every routing decision in ~/Library/Logs/DualPoint/DualPoint.log.
    private var verboseRouting: Bool {
        UserDefaults.standard.bool(forKey: "DualPointVerboseRouting")
    }

    private func trace(_ message: String) {
        guard verboseRouting else { return }
        log.trace("Route", message)
    }

    /// Whether this particular device can be isolated while it owns the blue
    /// pointer. The built-in trackpad has no raw HID reports to seize.
    private func canIsolate(deviceID: String) -> Bool {
        guard deviceID != DeviceIdentity.builtInTrackpadID,
              canIsolateExternalDevices,
              let info = connectedHID[deviceID],
              info.uniqueID != 0 else {
            return false
        }
        return true
    }

    public func device(withID id: String) -> PointingDevice? {
        devices.first { $0.id == id }
    }

    public var connectedDevices: [PointingDevice] {
        devices.filter(\.isConnected)
    }

    public var managedDevices: [PointingDevice] {
        devices.filter { $0.isConnected && $0.isManaged }
    }

    public var statusSummary: String {
        if !hasCompletedOnboarding && !isTestDriving { return "Finish setup to enable switching" }
        if !permissions.hidAccessGranted || !permissions.listenEventAccessGranted {
            return "Input Monitoring permission required"
        }
        if !eventTap.state.isRunning { return "Pointer monitoring unavailable" }
        if !automaticSwitching { return "Automatic switching is off" }
        if managedDevices.isEmpty { return "Assign a device to a display" }
        if let interimDevice { return "Interim: \(interimDevice.name)" }
        if let activeDevice { return "Active: \(activeDevice.name)" }
        return "Ready · waiting for input"
    }

    // MARK: - User actions

    public func setAutomaticSwitching(_ enabled: Bool) {
        guard automaticSwitching != enabled else { return }
        automaticSwitching = enabled
        if !enabled {
            clearSwitchCandidate()
            hideInterimCursor(persist: true)
        }
        store.update { $0.automaticSwitching = enabled }
        log.info("Settings", "Automatic switching \(enabled ? "enabled" : "disabled")")
    }

    public func setInterimCursorEnabled(_ enabled: Bool) {
        guard interimCursorEnabled != enabled else { return }
        interimCursorEnabled = enabled
        store.update { $0.interimCursorEnabled = enabled }
        syncInterimPolicy()
        if !enabled {
            hideInterimCursor(persist: true)
        }
        log.info("Settings", "Interim cursor \(enabled ? "enabled" : "disabled")")
    }

    public func setHandoverCooldown(_ seconds: TimeInterval) {
        let clamped = min(max(seconds, 0), 3)
        guard abs(handoverCooldown - clamped) > 0.001 else { return }
        handoverCooldown = clamped
        store.update { $0.handoverCooldown = clamped }
        syncInterimPolicy()
    }

    private func syncInterimPolicy() {
        arbiter.policy = InterimCursorPolicy(
            isEnabled: interimCursorEnabled,
            handoverCooldown: handoverCooldown
        )
    }

    /// Lets the setup assistant's final step test the real handover before the
    /// user commits to finishing setup.
    public func setTestDriving(_ active: Bool) {
        guard isTestDriving != active else { return }
        isTestDriving = active
        if !active {
            clearSwitchCandidate()
            hideInterimCursor(persist: true)
        }
        log.info("Setup", active ? "Test drive started" : "Test drive stopped")
    }

    public func setOnboardingCompleted(_ completed: Bool) {
        guard hasCompletedOnboarding != completed else { return }
        hasCompletedOnboarding = completed
        if !completed { hideInterimCursor(persist: true) }
        store.update { $0.onboardingCompleted = completed }
    }

    /// Marks setup as finished. If the user has not configured a single display
    /// assignment yet, the recommended layout is applied so DualPoint is useful
    /// immediately: trackpad on the built-in display, pointing devices on the
    /// first external display.
    public func completeOnboarding(applyRecommendedIfUnconfigured: Bool = true) {
        if applyRecommendedIfUnconfigured,
           connectedDevices.allSatisfy({ $0.assignment.isUnmanaged }) {
            _ = applyRecommendedSetup(quiet: true)
        }
        setTestDriving(false)
        setOnboardingCompleted(true)
        lastLoggedPermissionKey = ""
        log.info("Setup", "Onboarding completed")
        if !isSwitchingEnabled {
            log.info("Setup", statusSummary)
        }
    }

    public func resetOnboarding() {
        setOnboardingCompleted(false)
        log.info("Setup", "Onboarding reset")
    }

    @discardableResult
    public func applyRecommendedSetup(quiet: Bool = false) -> Int {
        let builtInDisplay = displays.first(where: \.isBuiltIn) ?? displays.first(where: \.isMain)
        let externalDisplay = displays.first(where: { !$0.isBuiltIn }) ?? builtInDisplay

        var changed = 0
        store.update { state in
            for device in self.connectedDevices {
                let target = device.kind == .builtInTrackpad ? builtInDisplay : externalDisplay
                guard let target else { continue }
                state.update(deviceID: device.id) { settings in
                    settings.assignment = DisplayAssignment(
                        displayUUID: target.id,
                        displayName: target.name
                    )
                    settings.isEnabled = true
                }
                changed += 1
            }
        }

        rebuildDevices()
        if !quiet {
            log.info("Setup", "Applied recommended display assignments to \(changed) device(s)")
        }
        return changed
    }

    public func assign(deviceID: String, to display: DisplayInfo?) {
        let assignment = display.map {
            DisplayAssignment(displayUUID: $0.id, displayName: $0.name)
        } ?? .unmanaged

        store.update { state in
            state.update(deviceID: deviceID) { settings in
                settings.assignment = assignment
            }
        }
        rebuildDevices()

        if let display {
            log.info("Settings", "\(deviceName(for: deviceID)) assigned to \(display.name)")
        } else {
            log.info("Settings", "\(deviceName(for: deviceID)) set to Unmanaged")
        }
    }

    public func setEnabled(deviceID: String, enabled: Bool) {
        if !enabled {
            if interimDeviceID == deviceID {
                hideInterimCursor(persist: true)
            }
            if activeDeviceID == deviceID {
                persistActiveAnchor(force: true)
                activeDeviceID = nil
                cachedActiveAnchor = nil
                arbiter.setMain(nil)
                hideInterimCursor(persist: true)
            }
        }
        store.update { state in
            state.update(deviceID: deviceID) { $0.isEnabled = enabled }
        }
        rebuildDevices()
        log.info("Settings", "\(deviceName(for: deviceID)) \(enabled ? "enabled" : "disabled")")
    }

    /// Places the cursor using this device's saved position or assignment.
    /// Used by the "Move Cursor Now" button for verifying a configuration.
    public func activate(deviceID: String) {
        guard let device = devices.first(where: { $0.id == deviceID }),
              device.isConnected, device.isEnabled else { return }

        let didWarp = performSwitch(to: device, source: "manual")
        if !didWarp, device.isManaged {
            log.warning("Switch", "\(device.name) has no reachable saved position or display assignment")
        }
    }

    public func resetPosition(deviceID: String) {
        if interimDeviceID == deviceID {
            hideInterimCursor(persist: false)
        }
        store.update { state in
            state.update(deviceID: deviceID) { $0.anchor = nil }
        }
        if activeDeviceID == deviceID {
            cachedActiveAnchor = nil
        }
        rebuildDevices()
        log.info("Settings", "Cleared saved position for \(deviceName(for: deviceID))")
    }

    public func resetAllPositions() {
        store.update { state in
            for id in Array(state.devices.keys) {
                state.update(deviceID: id) { $0.anchor = nil }
            }
        }
        cachedActiveAnchor = nil
        rebuildDevices()
        log.info("Settings", "Cleared every saved cursor position")
    }

    public func forgetDevice(deviceID: String) {
        guard connectedHID[deviceID] == nil else { return }
        if interimDeviceID == deviceID {
            hideInterimCursor(persist: false)
        }
        store.update { $0.devices.removeValue(forKey: deviceID) }
        if activeDeviceID == deviceID {
            activeDeviceID = nil
            cachedActiveAnchor = nil
            arbiter.setMain(nil)
            hideInterimCursor(persist: false)
        }
        rebuildDevices()
        log.info("Devices", "Removed saved settings for \(deviceID)")
    }

    // MARK: - Permissions

    public func refreshPermissions() {
        refreshPermissionsAndMonitoring()
    }

    public func requestInputMonitoring() {
        let granted = PermissionCenter.requestInputMonitoring()
        log.info("Permission", granted
            ? "Input Monitoring granted"
            : "Input Monitoring requested; waiting for approval in System Settings")
        refreshPermissionsAndMonitoring()
    }

    public func requestAccessibility() {
        let granted = PermissionCenter.requestAccessibility()
        log.info("Permission", granted
            ? "Accessibility granted"
            : "Accessibility requested; waiting for approval in System Settings")
        refreshPermissionsAndMonitoring()
    }

    public func openInputMonitoringSettings() {
        PermissionCenter.openInputMonitoringSettings()
    }

    public func openAccessibilitySettings() {
        PermissionCenter.openAccessibilitySettings()
    }

    public func openLoginItemsSettings() {
        PermissionCenter.openLoginItemsSettings()
    }

    public func relaunch() {
        PermissionCenter.quitAndReopen()
    }

    // MARK: - Monitor wiring

    private func configureCallbacks() {
        hidMonitor.onOwnershipChange = { [weak self] uniqueID, seized in
            self?.trace("HID ownership uniqueID=\(uniqueID) \(seized ? "seized (exclusive)" : "released (closed)")")
        }
        hidMonitor.onDeviceAdded = { [weak self] info in
            self?.handleDeviceAdded(info)
        }
        hidMonitor.onDeviceRemoved = { [weak self] id in
            self?.handleDeviceRemoved(id)
        }
        hidMonitor.onActivity = { [weak self] activity in
            self?.handleHIDActivity(activity)
        }
        hidMonitor.onError = { [weak self] message in
            self?.lastErrorMessage = message
            self?.log.error("HID", message)
        }
        hidMonitor.onBuiltInTrackpadSeen = { [weak self] in
            self?.markBuiltInTrackpadAvailable()
        }

        eventTap.onPointerEvent = { [weak self] event in
            self?.handlePointerEvent(event) ?? .pass
        }
        eventTap.onStateChange = { [weak self] state in
            self?.handleEventTapState(state)
        }

        hidMonitor.onSeizedMovement = { [weak self] movement in
            self?.handleSecondaryMovement(movement)
        }
        hidMonitor.onSeizedScroll = { [weak self] scroll in
            self?.handleSecondaryScroll(scroll)
        }
        hidMonitor.onSeizedButton = { [weak self] button in
            self?.handleSecondaryButton(button)
        }

        displayManager.onChange = { [weak self] displays in
            self?.handleDisplayChange(displays)
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissionsAndMonitoring()
            }
        })
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func refreshPermissionsAndMonitoring() {
        guard started else { return }

        var snapshot = PermissionCenter.snapshot(eventTapAvailable: eventTap.state.isRunning)

        if snapshot.hidAccessGranted {
            if !hidMonitor.isOpen {
                // A previous open may have failed before the permission was
                // granted. Tear the manager down and enumerate again.
                connectedHID.removeAll()
                activityTable.clear()
                hidMonitor.stop()
                hidMonitor.start()
            }
        } else if hidMonitor.isOpen {
            teardownHIDMonitorForPermissionLoss()
        }

        if snapshot.listenEventAccessGranted, !eventTap.state.isRunning {
            eventTap.start()
        }

        snapshot = PermissionCenter.snapshot(eventTapAvailable: eventTap.state.isRunning)
        permissions = snapshot
        eventTapFailure = eventTap.state.failureReason
        isMonitoring = hidMonitor.isOpen && eventTap.state.isRunning
        if !isSwitchingEnabled {
            hideInterimCursor(persist: true)
        }
        rebuildDevices()

        let permissionKey = [
            snapshot.hidAccessGranted ? "hid" : "-",
            snapshot.listenEventAccessGranted ? "listen" : "-",
            snapshot.eventTapAvailable ? "tap" : "-",
            snapshot.accessibilityTrusted ? "ax" : "-"
        ].joined(separator: "/")
        if permissionKey != lastLoggedPermissionKey {
            lastLoggedPermissionKey = permissionKey
            log.info("Permission", permissionKey)
        }

        if isMonitoring && snapshot.isReadyForAutomaticSwitching {
            stopPermissionTimer()
        } else {
            startPermissionTimer()
        }
    }

    private func teardownHIDMonitorForPermissionLoss() {
        hideInterimCursor(persist: true)
        if let activeDeviceID, activeDeviceID != DeviceIdentity.builtInTrackpadID {
            persistActiveAnchor(force: true)
            self.activeDeviceID = nil
            cachedActiveAnchor = nil
            arbiter.setMain(nil)
        }
        hidMonitor.stop()
        connectedHID.removeAll()
        activityTable.clear()
        rebuildDevices()
        log.warning("Permission", "Input Monitoring is no longer available; HID monitoring stopped")
    }

    private func handleEventTapState(_ state: EventTapMonitor.State) {
        eventTapFailure = state.failureReason
        permissions = PermissionCenter.snapshot(eventTapAvailable: state.isRunning)
        isMonitoring = hidMonitor.isOpen && state.isRunning

        switch state {
        case .running:
            log.info("EventTap", "Pointer event tap running")
            lastLoggedEventTapFailure = nil
        case .failed(let reason):
            hideInterimCursor(persist: true)
            if lastLoggedEventTapFailure != reason {
                lastLoggedEventTapFailure = reason
                log.error("EventTap", reason)
            }
        case .stopped:
            hideInterimCursor(persist: true)
        }
    }

    private func startPermissionTimer() {
        guard !permissionTimerIsRunning else { return }
        permissionTimerIsRunning = true
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissionsAndMonitoring()
            }
        }
    }

    private func stopPermissionTimer() {
        guard permissionTimerIsRunning else { return }
        permissionTimerIsRunning = false
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - HID devices

    private func handleDeviceAdded(_ info: HIDDeviceInfo) {
        migrateStoredSettingsIfNeeded(for: info)
        connectedHID[info.key] = info
        if info.kind == .builtInTrackpad {
            markBuiltInTrackpadAvailable()
        }
        log.info("Devices", "Connected \(info.name) [\(info.key)]")
        trace("HID device added \(info.key) uniqueID=\(info.uniqueID)")
        rebuildDevices()
    }

    /// USB location IDs change when a device moves to another port or hub.
    /// That produces a new identity key and would otherwise lose the display
    /// assignment and saved position. When exactly one disconnected record
    /// matches the same vendor/product, name and kind, carry its settings over
    /// to the new key.
    private func migrateStoredSettingsIfNeeded(for info: HIDDeviceInfo) {
        guard !info.isBuiltIn,
              info.kind == .mouse || info.kind == .trackpad || info.kind == .other else {
            return
        }

        let prefix = String(format: "hid:%04x:%04x", info.vendorID ?? 0, info.productID ?? 0)
        let candidates = store.state.devices.compactMap { id, settings -> String? in
            guard id != info.key,
                  id.hasPrefix(prefix),
                  connectedHID[id] == nil,
                  settings.lastKnownKind == info.kind,
                  settings.lastKnownName == info.name else {
                return nil
            }
            return id
        }
        guard candidates.count == 1, let previousID = candidates.first else { return }

        var migrated = false
        store.update { state in
            migrated = state.migrateSettings(from: previousID, to: info.key)
        }

        if migrated {
            log.info("Devices", "Moved saved settings for \(info.name) to its new connection [\(info.key)]")
        }
    }

    private func handleDeviceRemoved(_ id: String) {
        guard connectedHID.removeValue(forKey: id) != nil else { return }
        activityTable.remove(deviceID: id)

        if interimDeviceID == id {
            hideInterimCursor(persist: true)
            log.info("Interim", "Interim device disconnected: \(id)")
        }

        if activeDeviceID == id {
            persistActiveAnchor(force: true)
            activeDeviceID = nil
            cachedActiveAnchor = nil
            arbiter.setMain(nil)
            hideInterimCursor(persist: true)
            log.info("Devices", "Active device disconnected: \(id)")
        } else {
            log.info("Devices", "Disconnected \(id)")
        }
        rebuildDevices()
    }

    private func markBuiltInTrackpadAvailable() {
        guard !builtInTrackpadAvailable else { return }
        builtInTrackpadAvailable = true
        rebuildDevices()
    }

    private func handleDisplayChange(_ newDisplays: [DisplayInfo]) {
        hideInterimCursor(persist: true)
        displays = newDisplays
        rebuildDevices()

        let cursor = CursorController.currentPosition()
        if CursorGeometry.isPointOnAnyDisplay(cursor, displays: newDisplays) {
            if activeDeviceID != nil {
                captureActiveAnchor(at: cursor, forcePersist: true)
            }
        } else if let activeDevice, activeDevice.isManaged,
                  let point = CursorGeometry.restorePoint(
                    settings: store.state.settings(for: activeDevice.id),
                    displays: newDisplays
                  ) {
            _ = CursorController.warp(to: point)
            anchorCaptureFloor = Clock.nowNanoseconds()
            cachedActiveAnchor = CursorGeometry.anchor(for: point, in: newDisplays)
            log.warning("Display", "Cursor was outside every display; restored \(activeDevice.name)")
        } else if let main = newDisplays.first(where: \.isMain) ?? newDisplays.first {
            // The display the cursor lived on disappeared. Keep the pointer
            // visible instead of leaving it in now-invalid coordinates.
            let point = CursorGeometry.defaultPoint(for: main)
            _ = CursorController.warp(to: point)
            anchorCaptureFloor = Clock.nowNanoseconds()
            cachedActiveAnchor = CursorGeometry.anchor(for: point, in: newDisplays)
            log.warning("Display", "Cursor was outside every display; moved to \(main.name)")
        }

        log.info("Display", "Configuration changed: \(newDisplays.map(\.name).joined(separator: ", "))")
    }

    // MARK: - Interaction

    private func handleHIDActivity(_ activity: HIDActivity) {
        guard isRunning else { return }

        // A seized device is read exclusively through SecondaryPointerMonitor.
        // Leaving its reports in the attribution table lets a stale sample
        // capture an unmatched trackpad event and move the wrong pointer.
        let isSeized = activity.deviceID == seizedHIDKey
        if !isSeized {
            activityTable.record(
                deviceID: activity.deviceID,
                timestamp: activity.timestamp,
                isMovement: activity.isMovement
            )
        }

        guard connectedHID[activity.deviceID] != nil else { return }
        guard activity.isMovement || activity.isButtonPress else { return }

        let now = Clock.nowNanoseconds()
        if isSeized {
            // Raw movement and buttons already drive the arbiter and the ghost
            // through the secondary monitor. Avoid double counting here.
            return
        }
        if activity.isMovement {
            lastHIDMovementAt = now
            arbiter.noteMovement(activity.deviceID, at: now)
        }

        if activity.isMovement {
            if activity.deviceID != activeDeviceID {
                // While the interim cursor is visible, only the pointer event
                // may commit it. HID activity must not steal the handover and
                // warp the real cursor to a different saved position first.
                if arbiter.interimDeviceID != nil {
                    clearSwitchCandidate()
                    return
                }
                // Leave the overlap to the pointer event, which starts the
                // interim cursor. If this device cannot be isolated, fall
                // through to the normal single-device switch instead.
                if canUseInterimCursor,
                   now >= interimRefractoryUntil,
                   canIsolate(deviceID: activity.deviceID),
                   arbiter.canStartInterim(for: activity.deviceID, at: now) {
                    clearSwitchCandidate()
                    return
                }
            }
        } else if activity.isButtonPress,
                  arbiter.interimDeviceID != nil,
                  activity.deviceID != activeDeviceID {
            // A button press is handled by the event tap so the click lands at
            // the interim cursor's position.
            clearSwitchCandidate()
            return
        }

        noteInteraction(
            deviceID: activity.deviceID,
            isButtonPress: activity.isButtonPress,
            source: "HID"
        )
    }

    private func handlePointerEvent(_ event: PointerEvent) -> PointerEventDecision {
        guard isRunning, event.isMeaningfulActivity else { return .pass }
        let now = Clock.nowNanoseconds()

        let deviceID: String
        let isInferredBuiltIn: Bool
        // A movement report older than ~12 ms is not a plausible explanation
        // for this event. Without this, the trackpad's events are attributed to
        // a mouse that moved a moment earlier and both pointers follow it.
        let movementAttributionWindow: UInt64 = 12_000_000
        let matchedEntry = activityTable.device(forEventAt: event.timestamp)
        let isFreshMovementMatch: Bool
        if let entry = matchedEntry, event.isMovement {
            isFreshMovementMatch = event.timestamp >= entry.timestamp
                && event.timestamp - entry.timestamp <= movementAttributionWindow
        } else {
            isFreshMovementMatch = true
        }
        if let entry = matchedEntry,
           isFreshMovementMatch,
           connectedHID[entry.deviceID] != nil {
            deviceID = entry.deviceID
            isInferredBuiltIn = false
            unmatchedStreak = 0
        } else {
            // No HID report explains this event. On Apple Silicon the built-in
            // trackpad is a DriverKit event service, so this is its only signal.
            guard builtInTrackpadAvailable else { return .pass }
            deviceID = DeviceIdentity.builtInTrackpadID
            isInferredBuiltIn = true
            recordUnmatchedEvent(at: now)
        }

        if event.isMovement {
            arbiter.noteMovement(deviceID, at: now)
        }

        trace("event t\(event.type.rawValue) delta=(\(event.deltaX),\(event.deltaY)) matched=\(matchedEntry?.deviceID ?? "none") → \(deviceID)\(isInferredBuiltIn ? "(inferred)" : "") active=\(activeDeviceID ?? "none") interim=\(arbiter.interimDeviceID ?? "none") seized=\(seizedHIDKey ?? "none")")

        // 1. The interim device never steers the real cursor. Its movement
        //    drives the blue overlay instead.
        if arbiter.interimDeviceID == deviceID {
            return handleInterimPointerEvent(event, deviceID: deviceID, now: now)
        }

        // 2. The HID callbacks and the event tap are independent delivery paths
        //    and not perfectly ordered. While an external device is
        //    demonstrably streaming, one unmatched event is almost certainly a
        //    delayed report of that device. A sustained unmatched stream is the
        //    built-in trackpad.
        if isInferredBuiltIn,
           shouldIgnoreIsolatedUnmatchedEvent(event: event) {
            clearSwitchCandidate()
            return .pass
        }

        // 3. The device that owns the real cursor: normal, untouched fast path.
        // While the blue pointer is visible, its owner must never run the settle
        // timer. Otherwise a trackpad nudge is followed by a warp back to the
        // blue position and the two pointers appear welded together.
        if deviceID == activeDeviceID {
            if event.isMovement {
                if arbiter.interimDeviceID != nil {
                    suppressInterimAdoption(reason: "main device is moving")
                }
                captureActiveAnchor(at: event.location, eventTimestamp: event.timestamp)
            }
            return .pass
        }

        // 4. A second device moving while the first one is still moving gets the
        //    interim cursor instead of stealing the real one.
        if event.isMovement,
           canUseInterimCursor,
           now >= interimRefractoryUntil,
           canIsolate(deviceID: deviceID),
           arbiter.canStartInterim(for: deviceID, at: now),
           let device = devices.first(where: { $0.id == deviceID }),
           device.isManaged,
           let start = CursorGeometry.restorePoint(
               settings: store.state.settings(for: deviceID),
               displays: displays
           ) {
            beginInterimCursor(
                deviceID: deviceID,
                startPoint: start,
                reason: "both devices are moving"
            )
            return .consume
        }

        // 5. Normal single-device handover.
        let result = noteInteraction(
            deviceID: deviceID,
            isButtonPress: event.isButtonDown,
            source: isInferredBuiltIn ? "system pointer" : "pointer"
        )
        if result.switched && !result.didWarp {
            captureActiveAnchor(at: event.location, eventTimestamp: event.timestamp)
        }
        return .pass
    }

    private func recordUnmatchedEvent(at now: UInt64) {
        if now &- lastUnmatchedAt > 80_000_000 {
            unmatchedStreak = 1
        } else {
            unmatchedStreak += 1
        }
        lastUnmatchedAt = now
    }

    private func shouldIgnoreIsolatedUnmatchedEvent(event: PointerEvent) -> Bool {
        // While simultaneous cursors are enabled, an unmatched event while the
        // main device is moving is the signal that starts the blue cursor.
        // Ignoring it here would let the trackpad move the real cursor first.
        guard !canUseInterimCursor else { return false }
        guard let activeID = activeDeviceID,
              activeID != DeviceIdentity.builtInTrackpadID,
              connectedHID[activeID] != nil,
              Clock.nowNanoseconds() &- lastHIDMovementAt < 75_000_000 else {
            return false
        }
        // Three or more consecutive unmatched events are a real trackpad
        // stream, not a single report that lost the attribution race.
        return unmatchedStreak < 3
    }

    private func handleInterimPointerEvent(
        _ event: PointerEvent,
        deviceID: String,
        now: UInt64
    ) -> PointerEventDecision {
        guard canUseInterimCursor else {
            hideInterimCursor(persist: true)
            return .pass
        }

        if interimIsSeized {
            // A seized device cannot move the real pointer. Its raw reports
            // drive the ghost; any late event still has to be dropped.
            if event.isMovement {
                trace("interim \(deviceID) seized → consume late event d=(\(event.deltaX),\(event.deltaY))")
            }
            return event.isMovement ? .consume : .pass
        }

        if event.isMovement {
            let start = interimPoint ?? CursorController.currentPosition()
            let point = CursorGeometry.movedPoint(
                from: start,
                by: CGSize(width: CGFloat(event.deltaX), height: CGFloat(event.deltaY)),
                in: displays
            )
            moveInterimCursor(to: point)
            return .consume
        }

        if event.isButtonDown || event.isScroll {
            guard let point = interimPoint else { return .pass }
            // Clicking or scrolling with the interim device is an explicit
            // commitment to its position, so it ends the interim state even
            // during the cooldown.
            adoptInterimCursor(
                at: now,
                reason: event.isButtonDown ? "button press" : "scroll"
            )
            return .passAt(point)
        }

        return .pass
    }

    // MARK: - Interim cursor

    private func beginInterimCursor(
        deviceID: String,
        startPoint: CGPoint,
        reason: String
    ) {
        guard canUseInterimCursor,
              Clock.nowNanoseconds() >= interimRefractoryUntil,
              deviceID != activeDeviceID,
              let device = devices.first(where: { $0.id == deviceID }),
              device.isManaged else {
            return
        }
        trace("beginInterim device=\(deviceID) \(device.name) reason=\(reason)")

        // Only a device that can be seized may own the blue pointer. Consuming
        // a CGEvent does not stop the window server from moving the real cursor,
        // so the event-tap fallback is not a valid way to isolate a device.
        hideInterimCursor(persist: false, announce: false)
        guard canIsolate(deviceID: deviceID),
              let info = connectedHID[deviceID],
              hidMonitor.seize(deviceUniqueID: info.uniqueID) else {
            log.warning("Interim", "\(device.name) cannot be seized; keeping one real cursor")
            return
        }

        // A seized device's physical movement never reaches the event tap, so
        // the blue pointer starts exactly at this device's saved position.
        let point = startPoint

        interimIsSeized = true
        seizedHIDKey = deviceID
        arbiter.startInterim(deviceID)
        interimDeviceID = deviceID
        interimPoint = point
        startInterimTimer()
        onInterimCursorChange?(InterimCursor(
            deviceID: deviceID,
            deviceName: device.name,
            point: point
        ))
        log.info(
            "Interim",
            "\(device.name) shows an interim cursor at \(Self.format(point)); \(reason); raw HID (seized)"
        )
    }

    /// Raw HID counts are not screen points. This is DoubleMouse's gain curve:
    /// a linear ramp to 2x for fast strokes. HID X/Y are positive right/down,
    /// which is exactly Core Graphics' coordinate space — do not flip Y here.
    private static func rawGain(_ delta: CGPoint) -> CGFloat {
        1 + min(hypot(delta.x, delta.y), 40) / 40
    }

    private static func scaledRawDelta(_ delta: CGPoint) -> CGSize {
        let gain = rawGain(delta)
        return CGSize(width: delta.x * gain, height: delta.y * gain)
    }

    private func handleSecondaryMovement(_ movement: SecondaryPointerDelta) {
        guard isRunning,
              let deviceID = arbiter.interimDeviceID,
              interimIsSeized,
              connectedHID[deviceID]?.uniqueID == movement.deviceUniqueID,
              let point = interimPoint else {
            return
        }
        let now = Clock.nowNanoseconds()
        arbiter.noteMovement(deviceID, at: now)
        let scaled = Self.scaledRawDelta(movement.delta)
        let next = CursorGeometry.movedPoint(
            from: point,
            by: scaled,
            in: displays
        )
        trace("raw HID \(deviceID) dx=\(movement.delta.x) dy=\(movement.delta.y) gain=\(Self.rawGain(movement.delta)) → CG \(scaled.width),\(scaled.height)")
        moveInterimCursor(to: next)

        // A left button held on the blue pointer turns its movement into a
        // real drag. Every synthetic drag event returns the real cursor to the
        // main device immediately, so only the dragged window follows blue.
        guard interimButtonDown, let start = interimDragStartPoint else { return }
        // Capture fresh each time: the trackpad may keep moving the real cursor
        // while the blue pointer performs the drag.
        if !interimIsDragging, hypot(next.x - start.x, next.y - start.y) >= 3 {
            interimIsDragging = true
            CursorController.beginDrag(
                at: start,
                returningTo: CursorController.currentPosition()
            )
        }
        if interimIsDragging {
            CursorController.drag(
                to: next,
                returningTo: CursorController.currentPosition()
            )
        }
    }

    private func handleSecondaryScroll(_ scroll: SecondaryPointerScroll) {
        guard isRunning,
              let deviceID = arbiter.interimDeviceID,
              interimIsSeized,
              connectedHID[deviceID]?.uniqueID == scroll.deviceUniqueID,
              let point = interimPoint else {
            return
        }
        let returnPoint = CursorController.currentPosition()
        CursorController.scroll(
            at: point,
            horizontal: Int64(scroll.delta.x),
            vertical: Int64(scroll.delta.y),
            returningTo: returnPoint
        )
    }

    private func handleSecondaryButton(_ button: SecondaryPointerButton) {
        guard isRunning,
              let deviceID = arbiter.interimDeviceID,
              interimIsSeized,
              connectedHID[deviceID]?.uniqueID == button.deviceUniqueID,
              let point = interimPoint else {
            return
        }
        let mouseButton: CGMouseButton
        switch button.usage {
        case 2: mouseButton = .right
        case 3: mouseButton = .center
        default: mouseButton = .left
        }

        if button.isPressed {
            interimButtonDown = true
            interimDragStartPoint = point
            interimIsDragging = false
            // Like DoubleMouse, defer the event: a still-nothing click is posted
            // as down+up on release, and a drag posts its own down on threshold.
            return
        }

        guard interimButtonDown else { return }

        if mouseButton == .left, interimIsDragging {
            CursorController.endDrag(
                at: point,
                returningTo: CursorController.currentPosition()
            )
        } else {
            // No drag started: post both halves at once on release, restoring
            // the real cursor after each one.
            CursorController.click(
                at: point,
                button: mouseButton,
                isPressed: true,
                returningTo: CursorController.currentPosition()
            )
            CursorController.click(
                at: point,
                button: mouseButton,
                isPressed: false,
                returningTo: CursorController.currentPosition()
            )
        }
        resetInterimInputState()

        // A complete click commits the blue position to the external device,
        // but the real cursor stays where the main device left it.
        adoptInterimCursor(at: Clock.nowNanoseconds(), reason: "button click")
    }

    private func moveInterimCursor(to point: CGPoint) {
        guard let deviceID = arbiter.interimDeviceID else { return }
        interimPoint = point
        onInterimCursorChange?(InterimCursor(
            deviceID: deviceID,
            deviceName: deviceName(for: deviceID),
            point: point
        ))
    }

    /// Called when the real-cursor device moves during a dual-pointer session.
    /// It keeps dual mode until that device stops, then gives it a fresh settling
    /// window so a brief trackpad pause cannot trigger an adoption warp.
    private func suppressInterimAdoption(reason: String) {
        guard arbiter.interimDeviceID != nil else { return }
        let now = Clock.nowNanoseconds()
        arbiter.deferAdoption(
            until: now,
            for: max(arbiter.policy.handoverCooldown, Self.minimumInterimRefractory)
        )
        lastAutomaticSwitchAt = now
        lastHIDMovementAt = now
        lastUnmatchedAt = now
        unmatchedStreak = 0
        trace("interim adoption suppressed: \(reason)")
    }

    private func resetInterimInputState() {
        interimButtonDown = false
        interimDragStartPoint = nil
        interimIsDragging = false
    }

    private func hideInterimCursor(persist: Bool, announce: Bool = true) {
        if persist,
           let point = interimPoint,
           let deviceID = arbiter.interimDeviceID,
           let anchor = CursorGeometry.anchor(for: point, in: displays) {
            self.persist(anchor: anchor, for: deviceID)
        }
        let wasActive = arbiter.interimDeviceID != nil || interimPoint != nil
        hidMonitor.releaseSeized()
        interimIsSeized = false
        seizedHIDKey = nil
        arbiter.cancelInterim()
        interimDeviceID = nil
        interimPoint = nil
        resetInterimInputState()
        unmatchedStreak = 0
        stopInterimTimer()
        if announce && wasActive {
            onInterimCursorChange?(nil)
        }
    }

    private func startInterimTimer() {
        guard interimTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickInterimCursor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        interimTimer = timer
    }

    private func stopInterimTimer() {
        interimTimer?.invalidate()
        interimTimer = nil
    }

    private func tickInterimCursor() {
        guard let deviceID = arbiter.interimDeviceID else {
            stopInterimTimer()
            return
        }
        guard isRunning, canUseInterimCursor else {
            hideInterimCursor(persist: true)
            return
        }
        if deviceID != DeviceIdentity.builtInTrackpadID,
           connectedHID[deviceID] == nil {
            hideInterimCursor(persist: false)
            return
        }
        // Never move the real cursor in the middle of a drag.
        guard !interimButtonDown, !CursorController.isAnyButtonDown() else { return }
        guard arbiter.canAdoptInterim(at: Clock.nowNanoseconds()) else { return }
        adoptInterimCursor(at: Clock.nowNanoseconds(), reason: "settled")
    }

    private func adoptInterimCursor(at now: UInt64, reason: String) {
        guard let interimID = arbiter.interimDeviceID,
              let point = interimPoint else {
            return
        }

        // Save the blue pointer's final location as the external device's own
        // per-device position. Never write it to the active device: the real
        // cursor belongs to the main device (the built-in trackpad), and saving
        // that anchor here would make the trackpad jump to the external display
        // on the next switch.
        if let anchor = CursorGeometry.anchor(for: point, in: displays) {
            persist(anchor: anchor, for: interimID)
        }

        // Do NOT warp the real cursor to the blue pointer and do NOT re-anchor
        // the active device at this point. The real cursor has been moving with
        // the main device throughout and must stay exactly where the user left
        // it. Ending the session only removes the second pointer.
        let name = deviceName(for: interimID)
        lastAutomaticSwitchAt = now
        interimRefractoryUntil = now + Self.nanoseconds(
            max(handoverCooldown, Self.minimumInterimRefractory)
        )

        arbiter.finishInterim(at: now)
        clearSwitchCandidate()
        // Releases the seized device and removes the blue pointer. There is
        // exactly one cursor from here on: the real one, unchanged.
        hideInterimCursor(persist: false)
        rebuildDevices()

        log.info(
            "Interim",
            "\(name) position saved at \(Self.format(point)) (\(reason)); dual pointers removed; real cursor kept at \(Self.format(CursorController.currentPosition()))"
        )
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// Internal bounds that keep the user's delay slider from removing the
    /// settle behaviour entirely.
    private static let minimumInterimRefractory: TimeInterval = 0.7
    private static let minimumSwitchSpacing: TimeInterval = 0.25

    private static func format(_ point: CGPoint) -> String {
        String(format: "(%.0f, %.0f)", point.x, point.y)
    }

    @discardableResult
    private func noteInteraction(
        deviceID: String,
        isButtonPress: Bool,
        source: String
    ) -> (switched: Bool, didWarp: Bool) {
        guard let device = devices.first(where: { $0.id == deviceID }),
              device.isConnected, device.isEnabled else {
            return (false, false)
        }

        if activeDeviceID == deviceID {
            clearSwitchCandidate()
            return (false, false)
        }

        let now = Clock.nowNanoseconds()

        // The handover delay also applies after the blue pointer disappears.
        // Without this, releasing the seized mouse produces an immediate normal
        // switch back to its saved (blue) position, which looks like the real
        // cursor was warped there.
        if !isButtonPress, now < interimRefractoryUntil {
            clearSwitchCandidate()
            return (false, false)
        }

        if isSwitchingEnabled {
            // Never switch twice in quick succession from residual activity.
            // A deliberate button press is allowed through.
            if !isButtonPress,
               now &- lastAutomaticSwitchAt < Self.nanoseconds(Self.minimumSwitchSpacing) {
                clearSwitchCandidate()
                return (false, false)
            }

            // Do not yank the cursor during a drag. A new button press starts a
            // fresh interaction and is allowed to switch before the drag begins.
            if CursorController.isAnyButtonDown() && !isButtonPress {
                return (false, false)
            }

            // A single CGEvent can be misattributed while one device hands over
            // to another: the previous device's last HID report can still fall
            // inside the attribution window. Require the same new device to
            // produce a short burst before moving the cursor, so one stray
            // sample cannot visibly jump the pointer to the wrong display.
            if activeDeviceID != nil && !isButtonPress {
                let isContinuation = switchCandidateID == deviceID
                    && now &- switchCandidateAt <= 150_000_000
                switchCandidateID = deviceID
                switchCandidateCount = isContinuation ? switchCandidateCount + 1 : 1
                switchCandidateAt = now
                // Require two samples so a single stray event cannot move the
                // pointer to another display during a handover.
                let requiredCount = 2
                if switchCandidateCount < requiredCount {
                    return (false, false)
                }
            }

            clearSwitchCandidate()
            let didWarp = performSwitch(to: device, source: source)
            return (true, didWarp)
        }

        // Setup is incomplete or monitoring is paused. Remember the last used
        // device for the UI, but never move the cursor.
        clearSwitchCandidate()
        persistActiveAnchor(force: true)
        activeDeviceID = deviceID
        arbiter.setMain(deviceID)
        cachedActiveAnchor = nil
        hideInterimCursor(persist: true)
        rebuildDevices()
        log.info("Engine", "Activity from \(device.name) via \(source); switching is paused")
        return (false, false)
    }

    private func clearSwitchCandidate() {
        switchCandidateID = nil
        switchCandidateCount = 0
        switchCandidateAt = 0
    }

    private func performSwitch(to device: PointingDevice, source: String) -> Bool {
        let outgoing = activeDevice
        lastAutomaticSwitchAt = Clock.nowNanoseconds()
        persistActiveAnchor(force: true)
        hideInterimCursor(persist: true)

        activeDeviceID = device.id
        arbiter.setMain(device.id)
        cachedActiveAnchor = nil
        clearSwitchCandidate()
        var restoredPoint: CGPoint?
        var didWarp = false

        if device.isManaged {
            let settings = store.state.settings(for: device.id)
            if let point = CursorGeometry.restorePoint(settings: settings, displays: displays) {
                restoredPoint = point
                let current = CursorController.currentPosition()
                if current.distance(to: point) > 0.5 {
                    didWarp = CursorController.warp(to: point)
                    if didWarp {
                        anchorCaptureFloor = Clock.nowNanoseconds()
                    }
                }
                // Whether or not the position already matched, this anchor is
                // now the device's position.
                cachedActiveAnchor = CursorGeometry.anchor(for: point, in: displays)
            }
        }

        if cachedActiveAnchor == nil {
            let current = CursorController.currentPosition()
            cachedActiveAnchor = CursorGeometry.anchor(for: current, in: displays)
        }

        let switchRecord = SwitchRecord(
            deviceID: device.id,
            deviceName: device.name,
            fromDeviceID: outgoing?.id,
            restoredPoint: restoredPoint,
            wasWarped: didWarp
        )
        lastSwitch = switchRecord
        rebuildDevices()

        let fromName = outgoing?.name ?? "none"
        let target = restoredPoint.map { String(format: "(%.0f, %.0f)", $0.x, $0.y) } ?? "no saved position"
        log.info("Switch", "\(fromName) → \(device.name) via \(source), \(target)\(didWarp ? ", warped" : "")")
        return didWarp
    }

    private func captureActiveAnchor(
        at point: CGPoint,
        eventTimestamp: UInt64? = nil,
        forcePersist: Bool = false
    ) {
        if let eventTimestamp, eventTimestamp < anchorCaptureFloor {
            // A pointer event created before the last warp still refers to the
            // old position. Do not let it overwrite the freshly restored anchor.
            return
        }
        guard activeDeviceID != nil,
              CursorGeometry.isPointOnAnyDisplay(point, displays: displays),
              let anchor = CursorGeometry.anchor(for: point, in: displays) else {
            return
        }

        cachedActiveAnchor = anchor
        let now = Clock.nowNanoseconds()
        guard forcePersist || now &- lastAnchorPersist >= 500_000_000 else { return }
        persist(anchor: anchor, for: activeDeviceID)
        lastAnchorPersist = now
    }

    private func persistActiveAnchor(force: Bool) {
        guard let activeDeviceID else { return }
        guard let anchor = cachedActiveAnchor
            ?? CursorGeometry.anchor(for: CursorController.currentPosition(), in: displays) else {
            return
        }
        cachedActiveAnchor = anchor
        guard force || lastAnchorPersist == 0 else { return }
        persist(anchor: anchor, for: activeDeviceID)
        lastAnchorPersist = Clock.nowNanoseconds()
    }

    private func persist(anchor: CursorAnchor, for deviceID: String?) {
        guard let deviceID else { return }
        store.update { state in
            state.update(deviceID: deviceID) { $0.anchor = anchor }
        }
    }

    // MARK: - Device list

    private func rebuildDevices() {
        var result: [PointingDevice] = []
        var seen = Set<String>()

        if builtInTrackpadAvailable {
            let settings = store.state.settings(for: DeviceIdentity.builtInTrackpadID)
            result.append(PointingDevice(
                id: DeviceIdentity.builtInTrackpadID,
                name: "Built-in Trackpad",
                kind: .builtInTrackpad,
                isBuiltIn: true,
                vendorID: 0x05AC,
                isConnected: true,
                isEnabled: settings.isEnabled,
                assignment: settings.assignment,
                isActive: activeDeviceID == DeviceIdentity.builtInTrackpadID,
                hasSavedPosition: settings.anchor != nil
            ))
            seen.insert(DeviceIdentity.builtInTrackpadID)
        }

        let hidDevices = connectedHID.values.sorted {
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.key < $1.key
        }
        for info in hidDevices {
            seen.insert(info.key)
            let settings = store.state.settings(for: info.key)
            result.append(PointingDevice(
                id: info.key,
                name: info.name,
                kind: info.kind,
                isBuiltIn: info.isBuiltIn,
                vendorID: info.vendorID,
                productID: info.productID,
                locationID: info.locationID,
                serialNumber: info.serialNumber,
                transport: info.transport,
                isConnected: true,
                isEnabled: settings.isEnabled,
                assignment: settings.assignment,
                isActive: activeDeviceID == info.key,
                hasSavedPosition: settings.anchor != nil
            ))
        }

        for (id, settings) in store.state.devices where !seen.contains(id) {
            let kind = settings.lastKnownKind
                ?? (id == DeviceIdentity.builtInTrackpadID ? .builtInTrackpad : .other)
            result.append(PointingDevice(
                id: id,
                name: settings.lastKnownName ?? friendlyName(from: id),
                kind: kind,
                isBuiltIn: id == DeviceIdentity.builtInTrackpadID || kind == .builtInTrackpad,
                isConnected: false,
                isEnabled: settings.isEnabled,
                assignment: settings.assignment,
                isActive: activeDeviceID == id,
                hasSavedPosition: settings.anchor != nil
            ))
        }

        result.sort { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
            if lhs.name != rhs.name {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.id < rhs.id
        }

        devices = result
        rememberMetadata(for: result)
    }

    /// Stores names for devices that are no longer connected so the settings
    /// window can list them with a human-readable label.
    private func rememberMetadata(for devices: [PointingDevice]) {
        let connected = devices.filter(\.isConnected)
        let needsUpdate = connected.contains { device in
            let settings = store.state.settings(for: device.id)
            return settings.lastKnownName != device.name || settings.lastKnownKind != device.kind
        }
        guard needsUpdate else { return }

        store.update { state in
            for device in connected {
                state.update(deviceID: device.id) { settings in
                    if settings.lastKnownName != device.name {
                        settings.lastKnownName = device.name
                    }
                    if settings.lastKnownKind != device.kind {
                        settings.lastKnownKind = device.kind
                    }
                }
            }
        }
    }

    private func deviceName(for id: String) -> String {
        devices.first(where: { $0.id == id })?.name ?? friendlyName(from: id)
    }

    private func friendlyName(from id: String) -> String {
        if id.hasPrefix("hid:") { return "Previously connected device" }
        return id
    }
}

public extension PointingDevice {
    var assignmentDescription: String {
        if assignment.isUnmanaged { return "Unmanaged" }
        return assignment.displayName ?? "Assigned display"
    }
}
