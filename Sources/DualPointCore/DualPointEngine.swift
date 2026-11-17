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
/// the one that moved first keeps it and the other gets an app-drawn blue
/// interim cursor. The interim device's events are consumed by the event tap so
/// both devices can be positioned independently. When it settles, the real
/// cursor takes over its position.
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
    private var interimTimer: Timer?
    private var unmatchedStreak = 0
    private var lastUnmatchedAt: UInt64 = 0
    private var lastAccessibilityTrusted = false

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
        lastAccessibilityTrusted = false
        interimDeviceID = nil
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

    /// Accessibility plus an active event tap is what allows the interim
    /// device's movement to be consumed instead of steering the real cursor.
    /// This ignores the user's on/off setting so the UI can describe the
    /// permission itself.
    public var canSuppressPointerEvents: Bool {
        permissions.accessibilityTrusted && eventTap.canSuppressEvents
    }

    public var supportsInterimCursor: Bool {
        interimCursorEnabled && canSuppressPointerEvents
    }

    private var canUseInterimCursor: Bool {
        isSwitchingEnabled && supportsInterimCursor
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

        // An active tap can only suppress events with Accessibility. Restart
        // once when the permission is granted so the interim cursor starts
        // working without relaunching DualPoint.
        let accessibilityTrusted = snapshot.accessibilityTrusted
        if accessibilityTrusted, !lastAccessibilityTrusted,
           eventTap.state.isRunning, !eventTap.canSuppressEvents {
            eventTap.restart()
        }
        lastAccessibilityTrusted = accessibilityTrusted

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
        activityTable.record(
            deviceID: activity.deviceID,
            timestamp: activity.timestamp,
            isMovement: activity.isMovement
        )

        guard connectedHID[activity.deviceID] != nil else { return }
        guard activity.isMovement || activity.isButtonPress else { return }

        let now = Clock.nowNanoseconds()
        if activity.isMovement {
            lastHIDMovementAt = now
            arbiter.noteMovement(activity.deviceID, at: now)

            if activity.deviceID != activeDeviceID {
                // While the interim cursor is visible, only the pointer event
                // may commit it. HID activity must not steal the handover and
                // warp the real cursor to a different saved position first.
                let interimExists = arbiter.interimDeviceID != nil
                if interimExists || canUseInterimCursor {
                    if interimExists
                        || arbiter.canStartInterim(for: activity.deviceID, at: now) {
                        clearSwitchCandidate()
                        return
                    }
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
        if let entry = activityTable.device(forEventAt: event.timestamp),
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
        if deviceID == activeDeviceID {
            if event.isMovement {
                captureActiveAnchor(at: event.location, eventTimestamp: event.timestamp)
            }
            return .pass
        }

        // 4. A second device moving while the first one is still moving gets the
        //    interim cursor instead of stealing the real one.
        if event.isMovement,
           canUseInterimCursor,
           arbiter.canStartInterim(for: deviceID, at: now),
           let device = devices.first(where: { $0.id == deviceID }),
           device.isManaged,
           let start = CursorGeometry.restorePoint(
               settings: store.state.settings(for: deviceID),
               displays: displays
           ) {
            let point = CursorGeometry.movedPoint(
                from: start,
                by: CGSize(width: CGFloat(event.deltaX), height: CGFloat(event.deltaY)),
                in: displays
            )
            beginInterimCursor(
                deviceID: deviceID,
                point: point,
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

    private func beginInterimCursor(deviceID: String, point: CGPoint, reason: String) {
        guard canUseInterimCursor,
              deviceID != activeDeviceID,
              let device = devices.first(where: { $0.id == deviceID }),
              device.isManaged else {
            return
        }
        hideInterimCursor(persist: false, announce: false)
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
            "\(device.name) shows an interim cursor at \(Self.format(point)); \(reason)"
        )
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

    private func hideInterimCursor(persist: Bool, announce: Bool = true) {
        if persist,
           let point = interimPoint,
           let deviceID = arbiter.interimDeviceID,
           let anchor = CursorGeometry.anchor(for: point, in: displays) {
            self.persist(anchor: anchor, for: deviceID)
        }
        let wasActive = arbiter.interimDeviceID != nil || interimPoint != nil
        arbiter.cancelInterim()
        interimDeviceID = nil
        interimPoint = nil
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
        guard !CursorController.isAnyButtonDown() else { return }
        guard arbiter.canAdoptInterim(at: Clock.nowNanoseconds()) else { return }
        adoptInterimCursor(at: Clock.nowNanoseconds(), reason: "settled")
    }

    private func adoptInterimCursor(at now: UInt64, reason: String) {
        guard let interimID = arbiter.interimDeviceID,
              let point = interimPoint else {
            return
        }

        let outgoingID = activeDeviceID
        let outgoingPoint = CursorController.currentPosition()
        let outgoingRecentlyMoving = outgoingID.map {
            arbiter.isRecentlyMoving($0, at: now)
        } ?? false

        if let outgoingID,
           let outgoingAnchor = CursorGeometry.anchor(for: outgoingPoint, in: displays) {
            persist(anchor: outgoingAnchor, for: outgoingID)
        }
        let interimAnchor = CursorGeometry.anchor(for: point, in: displays)
        if let interimAnchor {
            persist(anchor: interimAnchor, for: interimID)
        }

        let name = deviceName(for: interimID)
        let didWarp = CursorController.warp(to: point)
        anchorCaptureFloor = now
        arbiter.adoptInterim(at: now)
        activeDeviceID = interimID
        cachedActiveAnchor = interimAnchor
        clearSwitchCandidate()
        hideInterimCursor(persist: false, announce: false)
        rebuildDevices()

        log.info(
            "Interim",
            "\(name) took over the real cursor at \(Self.format(point)) (\(reason))\(didWarp ? ", warped" : "")"
        )

        // If the previous main device is still moving, it becomes the new
        // interim cursor at the position the real cursor just left. The
        // cooldown then prevents an immediate second handover. Moving the same
        // overlay there avoids a visible flash between the two cursors.
        if let outgoingID, outgoingID != interimID, outgoingRecentlyMoving,
           let outgoing = devices.first(where: { $0.id == outgoingID }),
           outgoing.isManaged,
           CursorGeometry.isPointOnAnyDisplay(outgoingPoint, displays: displays) {
            beginInterimCursor(
                deviceID: outgoingID,
                point: outgoingPoint,
                reason: "the previous main device is still moving"
            )
        } else {
            onInterimCursorChange?(nil)
        }
    }

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

        if isSwitchingEnabled {
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
                let now = Clock.nowNanoseconds()
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
