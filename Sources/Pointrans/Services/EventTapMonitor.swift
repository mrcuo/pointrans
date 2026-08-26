import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum TriggerEvent: Sendable {
    case modifierPressed(point: CGPoint, timestamp: TimeInterval)
    case modifierReleased(point: CGPoint, timestamp: TimeInterval)
    case pointerMoved(point: CGPoint, timestamp: TimeInterval)
    case primaryClick(point: CGPoint, timestamp: TimeInterval)
}

enum EventTapRoutingPolicy {
    static func shouldForward(
        type: CGEventType,
        modifierIsDown: Bool,
        tracksPreviewPointer: Bool
    ) -> Bool {
        switch type {
        case .flagsChanged, .tapDisabledByTimeout, .tapDisabledByUserInput:
            true
        case .mouseMoved:
            modifierIsDown || tracksPreviewPointer
        case .leftMouseDown:
            tracksPreviewPointer
        default:
            false
        }
    }
}

private final class EventTapCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var modifierKeyCode: CGKeyCode
    private var modifierIsDown = false
    private var tracksPreviewPointer = false

    init(modifierKeyCode: CGKeyCode) {
        self.modifierKeyCode = modifierKeyCode
    }

    func updateModifierKeyCode(_ keyCode: CGKeyCode) {
        lock.withLock {
            modifierKeyCode = keyCode
            modifierIsDown = false
        }
    }

    func updatePreviewTracking(_ enabled: Bool) {
        lock.withLock { tracksPreviewPointer = enabled }
    }

    func shouldForward(type: CGEventType, event: CGEvent) -> Bool {
        let snapshot = lock.withLock { () -> (Bool, Bool) in
            if type == .flagsChanged {
                let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                if eventKeyCode == modifierKeyCode {
                    // Query the combined session only on the selected key's
                    // flags transition, never on every mouse-move callback.
                    modifierIsDown = CGEventSource.keyState(.combinedSessionState, key: modifierKeyCode)
                }
            }
            return (modifierIsDown, tracksPreviewPointer)
        }
        return EventTapRoutingPolicy.shouldForward(
            type: type,
            modifierIsDown: snapshot.0,
            tracksPreviewPointer: snapshot.1
        )
    }
}

@MainActor
final class EventTapMonitor {
    enum MonitorError: Error {
        case eventTapUnavailable
    }

    var onEvent: ((TriggerEvent) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifier: TriggerModifier
    private var isModifierDown = false
    private let callbackState: EventTapCallbackState

    init(modifier: TriggerModifier) {
        self.modifier = modifier
        callbackState = EventTapCallbackState(modifierKeyCode: modifier.keyCode)
    }

    func updateModifier(_ modifier: TriggerModifier) {
        guard self.modifier != modifier else { return }
        if isModifierDown {
            isModifierDown = false
            let point = CGEvent(source: nil)?.location ?? .zero
            onEvent?(.modifierReleased(point: point, timestamp: ProcessInfo.processInfo.systemUptime))
        }
        self.modifier = modifier
        callbackState.updateModifierKeyCode(modifier.keyCode)
    }

    func setPreviewPointerTracking(_ enabled: Bool) {
        callbackState.updatePreviewTracking(enabled)
    }

    func start() throws {
        stop()
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.mouseMoved.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            onAvailabilityChanged?(false)
            throw MonitorError.eventTapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        onAvailabilityChanged?(true)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        runLoopSource = nil
        eventTap = nil
        isModifierDown = false
        callbackState.updatePreviewTracking(false)
    }

    private struct RawEvent: Sendable {
        let typeRawValue: UInt32
        let point: CGPoint
        let keyCode: CGKeyCode
    }

    private func consume(_ raw: RawEvent) {
        let type = CGEventType(rawValue: raw.typeRawValue) ?? .null
        let point = raw.point
        let timestamp = ProcessInfo.processInfo.systemUptime
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                onAvailabilityChanged?(true)
            }

        case .flagsChanged:
            guard raw.keyCode == modifier.keyCode else { return }
            let pressed = CGEventSource.keyState(.combinedSessionState, key: modifier.keyCode)
            guard pressed != isModifierDown else { return }
            isModifierDown = pressed
            onEvent?(pressed
                ? .modifierPressed(point: point, timestamp: timestamp)
                : .modifierReleased(point: point, timestamp: timestamp))

        case .mouseMoved:
            // The callback already drops idle movement. Events also pass while a
            // transient Preview is tracking its safe corridor after key release.
            onEvent?(.pointerMoved(point: point, timestamp: timestamp))

        case .leftMouseDown:
            onEvent?(.primaryClick(point: point, timestamp: timestamp))

        default:
            break
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<EventTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        guard monitor.callbackState.shouldForward(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        let raw = RawEvent(
            typeRawValue: type.rawValue,
            point: event.location,
            keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        )
        if Thread.isMainThread {
            // The tap's source is installed on CFRunLoopGetMain(). Consuming
            // synchronously preserves modifier/mouse ordering and avoids
            // creating one unbounded MainActor task for every pointer event.
            MainActor.assumeIsolated {
                monitor.consume(raw)
            }
        } else {
            Task { @MainActor in
                monitor.consume(raw)
            }
        }
        return Unmanaged.passUnretained(event)
    }
}

private extension TriggerModifier {
    var keyCode: CGKeyCode {
        switch self {
        case .leftOption: CGKeyCode(kVK_Option)
        case .rightOption: CGKeyCode(kVK_RightOption)
        case .leftCommand: CGKeyCode(kVK_Command)
        case .rightCommand: CGKeyCode(kVK_RightCommand)
        case .leftControl: CGKeyCode(kVK_Control)
        case .rightControl: CGKeyCode(kVK_RightControl)
        case .leftShift: CGKeyCode(kVK_Shift)
        case .rightShift: CGKeyCode(kVK_RightShift)
        }
    }
}
