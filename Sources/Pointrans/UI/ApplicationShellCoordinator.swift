import AppKit
import SwiftUI

@MainActor
final class ApplicationShellCoordinator: NSObject {
    enum InitializationError: Error { case statusItemUnavailable }

    private let controller: TranslationController
    private let permissions: PermissionCoordinator
    private let languagePacks: LanguagePackManager
    private let preferences: AppPreferences
    private let statusBar: StatusBarController
    private let controlWindow: NSWindow
    private let onboardingWindow: NSWindow
    private let onboardingWindowDelegate: OnboardingWindowCloseDelegate
    private var recoveryCheck: Task<Void, Never>?

    init(
        controller: TranslationController,
        permissions: PermissionCoordinator,
        languagePacks: LanguagePackManager,
        preferences: AppPreferences,
        statusBar: StatusBarController
    ) {
        self.controller = controller
        self.permissions = permissions
        self.languagePacks = languagePacks
        self.preferences = preferences
        self.statusBar = statusBar
        onboardingWindowDelegate = OnboardingWindowCloseDelegate()

        controlWindow = Self.makeControlWindow(
            root: ControlCenterView(
                controller: controller,
                permissions: permissions,
                languagePacks: languagePacks
            )
        )

        var finishOnboarding: (() -> Void)?
        onboardingWindow = Self.makeOnboardingWindow(
            root: OnboardingView(
                controller: controller,
                permissions: permissions,
                languagePacks: languagePacks,
                onComplete: { finishOnboarding?() }
            )
        )

        super.init()

        onboardingWindow.delegate = onboardingWindowDelegate
        onboardingWindowDelegate.onClose = { NSApp.terminate(nil) }
        finishOnboarding = { [weak self] in self?.finishOnboarding() }
        statusBar.onLeftClick = { [weak self] in self?.toggleControlCenter() }
        statusBar.onOpen = { [weak self] in self?.showControlCenter() }
        statusBar.onTogglePaused = { [weak self] in
            guard let self else { return }
            self.controller.setTranslationEnabled(!self.preferences.translationEnabled)
            self.refreshPresentation()
        }
        statusBar.onQuit = { NSApp.terminate(nil) }

        controller.onStatusUpdate = { [weak self] in self?.refreshPresentation() }
        permissions.onChange = { [weak self] in
            self?.controller.refreshCapabilities()
            self?.refreshPresentation()
        }
        languagePacks.onChange = { [weak self] in self?.refreshPresentation() }
    }

    func launch() {
        statusBar.ensureVisible()
        permissions.refresh()
        refreshPresentation()
        scheduleStatusRecoveryCheck()
        if preferences.didCompleteOnboarding {
            languagePacks.beginRequiredPreparation()
            controller.start()
        } else {
            preferences.onboardingStage = normalizedStage(preferences.onboardingStage)
            showOnboarding()
        }
    }

    func applicationDidBecomeActive() {
        permissions.refresh()
        if preferences.didCompleteOnboarding,
           languagePacks.status != .checking,
           languagePacks.status != .preparing {
            languagePacks.beginRequiredPreparation()
        }
        controller.applicationDidBecomeActive()
        refreshPresentation()
    }

    func handleReopen() {
        if preferences.didCompleteOnboarding {
            showControlCenter()
        } else {
            showOnboarding()
        }
    }

    func stop() {
        recoveryCheck?.cancel()
        controller.stop()
        permissions.stop()
        controlWindow.orderOut(nil)
        onboardingWindow.orderOut(nil)
        statusBar.invalidate()
    }

    private func showOnboarding() {
        controlWindow.orderOut(nil)
        NSApp.activate()
        onboardingWindow.center()
        onboardingWindow.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        onboardingWindow.orderOut(nil)
        refreshPresentation()
        scheduleStatusRecoveryCheck()
    }

    private func toggleControlCenter() {
        if controlWindow.isVisible {
            controlWindow.orderOut(nil)
        } else {
            showControlCenter()
        }
    }

    private func showControlCenter() {
        guard preferences.didCompleteOnboarding else {
            showOnboarding()
            return
        }
        permissions.refresh()
        controller.closePanel()
        NSApp.activate()
        positionControlWindow()
        controlWindow.makeKeyAndOrderFront(nil)
    }

    private func positionControlWindow() {
        guard let anchor = statusBar.anchorRect,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else {
            controlWindow.center()
            return
        }
        var origin = CGPoint(
            x: anchor.midX - controlWindow.frame.width / 2,
            y: anchor.minY - controlWindow.frame.height - 7
        )
        let safe = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        origin.x = min(max(origin.x, safe.minX), safe.maxX - controlWindow.frame.width)
        origin.y = min(max(origin.y, safe.minY), safe.maxY - controlWindow.frame.height)
        controlWindow.setFrameOrigin(origin)
    }

    private func scheduleStatusRecoveryCheck() {
        recoveryCheck?.cancel()
        recoveryCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, !self.statusBar.hasUsableAnchor else { return }
            self.showControlCenter()
        }
    }

    private func refreshPresentation() {
        statusBar.ensureVisible()
        let readiness = readiness
        statusBar.update(readiness: readiness, isPaused: !preferences.translationEnabled)
    }

    private var readiness: AppReadiness {
        AppReadinessResolver.resolve(
            onboardingComplete: preferences.didCompleteOnboarding,
            translationEnabled: preferences.translationEnabled,
            accessibilityGranted: permissions.accessibilityGranted,
            screenCaptureGranted: permissions.screenCaptureGranted,
            languagePackStatus: languagePacks.status,
            triggerRuntimeState: controller.triggerRuntimeState
        )
    }

    private func normalizedStage(_ stage: OnboardingStage) -> OnboardingStage {
        switch stage {
        case .complete: .welcome
        default: stage
        }
    }

    private static func makeControlWindow(root: ControlCenterView) -> NSWindow {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pointrans"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: root)
        panel.setAccessibilityIdentifier("pointrans-control-center-window")
        return panel
    }

    private static func makeOnboardingWindow(root: OnboardingView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Pointrans"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentViewController = NSHostingController(rootView: root)
        window.setAccessibilityIdentifier("pointrans-onboarding-window")
        return window
    }
}

@MainActor
private final class OnboardingWindowCloseDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose?()
        return false
    }
}

@MainActor
final class StatusBarController: NSObject {
    var onLeftClick: (() -> Void)?
    var onOpen: (() -> Void)?
    var onTogglePaused: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let contextMenu = NSMenu()
    private let pauseItem = NSMenuItem()
    private var isInvalidated = false

    init(validating: Void) throws {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        guard let button = statusItem.button else {
            NSStatusBar.system.removeStatusItem(statusItem)
            throw ApplicationShellCoordinator.InitializationError.statusItemUnavailable
        }
        button.image = Self.makeTemplateIcon(attention: false, paused: false)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Pointrans"
        button.setAccessibilityLabel("Pointrans")
        button.target = self
        button.action = #selector(activateStatusItem)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityIdentifier("pointrans-menu-bar-button")

        contextMenu.addItem(withTitle: String(localized: "Open Control Center"), action: #selector(openControl), keyEquivalent: "")
        pauseItem.target = self
        pauseItem.action = #selector(togglePaused)
        contextMenu.addItem(pauseItem)
        contextMenu.addItem(.separator())
        contextMenu.addItem(withTitle: String(localized: "Quit Pointrans"), action: #selector(quit), keyEquivalent: "q")
        for item in contextMenu.items where item.target == nil { item.target = self }
    }

    func ensureVisible() {
        guard !isInvalidated else { return }
        statusItem.isVisible = true
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        contextMenu.cancelTracking()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    var anchorRect: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var hasUsableAnchor: Bool {
        guard statusItem.isVisible, let anchorRect, anchorRect.width > 4, anchorRect.height > 4 else { return false }
        return NSScreen.screens.contains { screen in
            let menuBand = CGRect(x: screen.frame.minX, y: screen.visibleFrame.maxY, width: screen.frame.width, height: screen.frame.maxY - screen.visibleFrame.maxY)
            return menuBand.intersects(anchorRect)
        }
    }

    func update(readiness: AppReadiness, isPaused: Bool) {
        ensureVisible()
        let isOnboarding = readiness == .onboarding
        statusItem.length = isOnboarding ? NSStatusItem.variableLength : NSStatusItem.squareLength
        statusItem.button?.title = isOnboarding ? " Pointrans" : ""
        statusItem.button?.imagePosition = isOnboarding ? .imageLeading : .imageOnly
        let attention: Bool = switch readiness {
        case .needsAccessibility, .needsScreenCapture, .listenerFailed, .fatalStartupError: true
        default: false
        }
        statusItem.button?.image = Self.makeTemplateIcon(attention: attention, paused: isPaused)
        statusItem.button?.toolTip = "Pointrans — \(tooltip(for: readiness))"
        pauseItem.title = isPaused ? String(localized: "Resume Translation") : String(localized: "Pause Translation")
    }

    @objc private func activateStatusItem() {
        if NSApp.currentEvent?.type == .rightMouseUp, let event = NSApp.currentEvent, let view = statusItem.button {
            NSMenu.popUpContextMenu(contextMenu, with: event, for: view)
        } else {
            onLeftClick?()
        }
    }

    @objc private func openControl() { onOpen?() }
    @objc private func togglePaused() { onTogglePaused?() }
    @objc private func quit() { onQuit?() }

    private func tooltip(for readiness: AppReadiness) -> String {
        switch readiness {
        case .ready: String(localized: "Ready to translate")
        case .paused: String(localized: "Translation is paused")
        case .needsAccessibility: String(localized: "Accessibility is required")
        case .needsScreenCapture: String(localized: "Screen Recording is required")
        case .recoveringListener: String(localized: "Restoring text detection…")
        case .listenerFailed: String(localized: "Text detection needs attention")
        case .onboarding: String(localized: "Setup is required")
        case .preparingLanguagePack: String(localized: "Preparing language capability…")
        case .launching: String(localized: "Starting…")
        case .fatalStartupError: String(localized: "Pointrans needs attention")
        }
    }

    private static func makeTemplateIcon(attention: Bool, paused: Bool) -> NSImage {
        let officialSymbol = Bundle.main
            .image(forResource: NSImage.Name("PointransSymbol"))?
            .copy() as? NSImage
        officialSymbol?.isTemplate = false
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            if let officialSymbol {
                officialSymbol.draw(
                    in: NSRect(x: 1.2, y: 1.2, width: 15.6, height: 15.6),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            } else {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 12, height: 12)).fill()
            }
            if attention {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 14.3, y: 1.1, width: 3.2, height: 3.2)).fill()
            }
            if paused {
                let slash = NSBezierPath()
                slash.lineWidth = 1.7
                slash.move(to: NSPoint(x: 2.5, y: 15.5))
                slash.line(to: NSPoint(x: 15.5, y: 2.5))
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pointrans"
        return image
    }
}
