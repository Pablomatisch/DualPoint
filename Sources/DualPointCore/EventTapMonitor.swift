import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

public struct PointerEvent {
    public let type: CGEventType
    public let timestamp: UInt64
    public let location: CGPoint
    public let deltaX: Int64
    public let deltaY: Int64
    public let scrollDeltaY: Int64
    public let scrollDeltaX: Int64
    public let isMomentumScroll: Bool
    public let isSynthetic: Bool

    public var isMovement: Bool {
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return deltaX != 0 || deltaY != 0
        default:
            return false
        }
    }

    public var isButtonDown: Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    public var isButtonUp: Bool {
        switch type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    public var isScroll: Bool {
        type == .scrollWheel
    }

    /// True when the event represents a deliberate new interaction that can
    /// reasonably trigger a device switch.
    public var isMeaningfulActivity: Bool {
        guard !isSynthetic else { return false }
        if isMovement { return true }
        if isButtonDown { return true }
        if isScroll && !isMomentumScroll && (scrollDeltaX != 0 || scrollDeltaY != 0) { return true }
        return false
    }

    public var debugSummary: String {
        var parts = ["type \(type.rawValue)"]
        if isMovement { parts.append("move \(deltaX),\(deltaY)") }
        if isScroll { parts.append("scroll \(scrollDeltaX),\(scrollDeltaY)\(isMomentumScroll ? " momentum" : "")") }
        if isButtonDown { parts.append("button down") }
        return parts.joined(separator: " ")
    }
}

/// What the event tap should do with a pointer event.
public enum PointerEventDecision: Equatable {
    /// Deliver the event unchanged.
    case pass
    /// Drop the event. The pointer does not move and no app sees it.
    case consume
    /// Deliver the event at a corrected global location.
    case passAt(CGPoint)
}

/// A CGEventTap that listens to pointer events.
///
/// It is created as a passive, listen-only tap unless Accessibility is granted.
/// With Accessibility it becomes an active tap, which lets DualPoint consume
/// the movement of an interim device so that device no longer steers the real
/// cursor. Single-device use always returns `.pass`; the tap only consumes
/// events while a second cursor is actually visible.
@MainActor
public final class EventTapMonitor {
    public enum State: Equatable {
        case stopped
        case running
        case failed(String)

        public var isRunning: Bool { self == .running }
        public var failureReason: String? {
            if case .failed(let reason) = self { return reason }
            return nil
        }
    }

    public var onPointerEvent: ((PointerEvent) -> PointerEventDecision)?
    public var onStateChange: ((State) -> Void)?

    public private(set) var state: State = .stopped
    /// True when the tap was created with Accessibility and can drop events.
    public private(set) var canSuppressEvents = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private static let eventMask = (1 << CGEventType.mouseMoved.rawValue)
        | (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.rightMouseDown.rawValue)
        | (1 << CGEventType.rightMouseUp.rawValue)
        | (1 << CGEventType.rightMouseDragged.rawValue)
        | (1 << CGEventType.otherMouseDown.rawValue)
        | (1 << CGEventType.otherMouseUp.rawValue)
        | (1 << CGEventType.otherMouseDragged.rawValue)
        | (1 << CGEventType.scrollWheel.rawValue)

    public init() {}

    @discardableResult
    public func start() -> Bool {
        if state.isRunning { return true }
        stop()

        let mask = CGEventMask(Self.eventMask)
        let wantsActiveTap = AXIsProcessTrusted()
        var created = wantsActiveTap
            ? createTap(options: .defaultTap, mask: mask)
            : nil
        var isActive = created != nil
        if created == nil {
            created = createTap(options: .listenOnly, mask: mask)
            isActive = false
        }
        guard let tap = created else {
            setState(.failed("macOS refused to create the input event tap. Input Monitoring or Accessibility permission is required."))
            return false
        }

        self.tap = tap
        canSuppressEvents = isActive
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        setState(.running)
        return true
    }

    /// Restarts a running tap so it picks up a newly granted Accessibility
    /// permission. Called only on the false→true transition, so a refused
    /// active tap is not retried in a loop.
    public func restart() {
        guard state.isRunning else { return }
        stop()
        start()
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
        canSuppressEvents = false
        setState(.stopped)
    }

    public func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        if !state.isRunning {
            setState(.running)
        }
    }

    private func createTap(options: CGEventTapOptions, mask: CGEventMask) -> CFMachPort? {
        let context = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: pointerEventCallback,
            userInfo: context
        )
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            return Unmanaged.passUnretained(event)
        }

        let pointer = PointerEvent(
            type: type,
            // CGEvent timestamps are mach absolute time ticks, just like HID
            // report timestamps. Normalize both to nanoseconds for attribution.
            timestamp: Clock.ticksToNanoseconds(event.timestamp),
            location: event.location,
            deltaX: event.getIntegerValueField(.mouseEventDeltaX),
            deltaY: event.getIntegerValueField(.mouseEventDeltaY),
            scrollDeltaY: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
            scrollDeltaX: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
            isMomentumScroll: event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0,
            isSynthetic: event.getIntegerValueField(.eventSourceUnixProcessID) != 0
        )

        switch onPointerEvent?(pointer) ?? .pass {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .consume:
            // A listen-only tap cannot drop events; never pretend it did.
            return canSuppressEvents ? nil : Unmanaged.passUnretained(event)
        case .passAt(let point):
            guard canSuppressEvents else { return Unmanaged.passUnretained(event) }
            event.location = point
            return Unmanaged.passUnretained(event)
        }
    }

    private func setState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }
}

private let pointerEventCallback: CGEventTapCallBack = { _, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<EventTapMonitor>.fromOpaque(context).takeUnretainedValue()
    return MainActor.assumeIsolated {
        monitor.handle(type: type, event: event)
    }
}
