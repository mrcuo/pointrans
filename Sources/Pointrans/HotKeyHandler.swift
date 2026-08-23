import Cocoa

@MainActor
class HotKeyHandler {
    static let shared = HotKeyHandler()

    private var globalMonitor: Any?
    private var hoverTimer: Timer?
    private var lastMouseLocation: NSPoint = .zero
    private var stationaryStart: TimeInterval?
    private var lastTranslatedLocation: NSPoint = .zero
    private var isArmed = false

    /// Triggered when the mouse is stationary with the modifier key held down for the delay duration.
    var onHoverTriggered: (@MainActor (NSPoint) -> Void)?

    /// Triggered when the mouse moves while the modifier key is held.
    var onMouseMoved: (@MainActor () -> Void)?

    /// Triggered when the modifier key is released.
    var onModifierReleased: (@MainActor () -> Void)?

    private init() {}

    func startMonitoring() {
        stopMonitoring()
        // Native global event monitor: modifier changes arrive as events, so we never
        // poll key state. The hover-delay timer only runs while the modifier is held.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleModifierFlags(event.modifierFlags)
            }
        }
    }

    func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        stopHoverTimer()
        isArmed = false
        stationaryStart = nil
    }

    private func handleModifierFlags(_ flags: NSEvent.ModifierFlags) {
        let pressed = isModifierPressed(in: flags)
        if pressed && !isArmed {
            arm()
        } else if !pressed && isArmed {
            disarm()
            onModifierReleased?()
        }
    }

    private func arm() {
        guard UserDefaults.standard.bool(forKey: "translationEnabled") else { return }
        isArmed = true
        lastMouseLocation = NSEvent.mouseLocation
        stationaryStart = ProcessInfo.processInfo.systemUptime
        startHoverTimer()
    }

    private func disarm() {
        stopHoverTimer()
        isArmed = false
        stationaryStart = nil
        // Reset so the user can immediately re-translate the same word.
        lastTranslatedLocation = .zero
    }

    private func startHoverTimer() {
        stopHoverTimer()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkHoverState()
            }
        }
    }

    private func stopHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func checkHoverState() {
        guard isArmed else { return }
        guard UserDefaults.standard.bool(forKey: "translationEnabled") else {
            disarm()
            return
        }

        let currentMouseLoc = NSEvent.mouseLocation
        let distance = abs(currentMouseLoc.x - lastMouseLocation.x) + abs(currentMouseLoc.y - lastMouseLocation.y)

        if distance < 3.0 {
            // Stationary: measure elapsed time with a monotonic clock instead of counting ticks.
            var delay = UserDefaults.standard.double(forKey: "hoverDelay")
            if delay <= 0 { delay = 0.3 }

            if let start = stationaryStart,
               ProcessInfo.processInfo.systemUptime - start >= delay {
                // Avoid re-triggering on the same word.
                let distFromLast = abs(currentMouseLoc.x - lastTranslatedLocation.x) + abs(currentMouseLoc.y - lastTranslatedLocation.y)
                if distFromLast > 15.0 {
                    lastTranslatedLocation = currentMouseLoc
                    onHoverTriggered?(currentMouseLoc)
                }
            }
        } else {
            // Mouse moved while modifier held.
            stationaryStart = ProcessInfo.processInfo.systemUptime
            onMouseMoved?()
        }

        lastMouseLocation = currentMouseLoc
    }

    private func isModifierPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        switch (UserDefaults.standard.string(forKey: "modifierKey") ?? "command").lowercased() {
        case "option":  return flags.contains(.option)
        case "control": return flags.contains(.control)
        case "shift":   return flags.contains(.shift)
        default:        return flags.contains(.command)
        }
    }

    func resetLastTranslationLocation() {
        lastTranslatedLocation = .zero
    }
}
