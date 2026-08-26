import AppKit
import SwiftUI

@MainActor
private final class TranslationPanelWindow: NSPanel {
    var permitsKey = false
    override var canBecomeKey: Bool { permitsKey }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TranslationPanelCoordinator {
    private let controller: TranslationController
    private let panel: TranslationPanelWindow
    private let hostingController: NSHostingController<TranslationCardView>
    private let isUITesting: Bool
    private var shownSessionID: UUID?

    init(controller: TranslationController, isUITesting: Bool = false) {
        self.controller = controller
        self.isUITesting = isUITesting
        hostingController = NSHostingController(rootView: TranslationCardView(controller: controller))
        panel = TranslationPanelWindow(
            contentRect: .zero,
            styleMask: isUITesting ? [.titled, .closable] : [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.alphaValue = 0
        panel.setAccessibilityIdentifier("translation-panel-window")

        controller.onPanelUpdate = { [weak self] in self?.synchronize() }
        if isUITesting {
            panel.title = "Pointrans Translation"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
        }
    }

    func synchronize() {
        switch controller.panelMode {
        case .hidden:
            hideAnimated()
        case .preview(let sessionID):
            show(sessionID: sessionID, pinned: false)
        case .pinned(let sessionID):
            show(sessionID: sessionID, pinned: true)
        }
    }

    private func show(sessionID: UUID, pinned: Bool) {
        guard let request = controller.currentRequest, request.id == sessionID else { return }
        let size = pinned ? CGSize(width: 420, height: 372) : CGSize(width: 360, height: 210)
        panel.permitsKey = pinned
        if isUITesting {
            panel.styleMask.remove(.nonactivatingPanel)
        } else if pinned {
            panel.styleMask.remove(.nonactivatingPanel)
        } else {
            panel.styleMask.insert(.nonactivatingPanel)
        }

        let appKitAnchor = ScreenCoordinates.quartzToAppKit(request.screenPoint)
        let screen = ScreenCoordinates.screen(for: request.displayID) ??
            NSScreen.screens.first(where: { $0.frame.contains(appKitAnchor) }) ??
            NSScreen.main
        guard let screen else { return }
        shownSessionID = sessionID
        let origin = ScreenCoordinates.stablePanelOrigin(anchor: appKitAnchor, panelSize: size, screen: screen)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        controller.updatePanelFrame(appKitFrame: panel.frame)

        if pinned {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideAnimated() {
        guard let capturedSession = shownSessionID else { return }
        guard panel.isVisible else {
            shownSessionID = nil
            controller.panelHideAnimationCompleted(sessionID: capturedSession)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.shownSessionID == capturedSession,
                      self.controller.panelMode == .hidden else { return }
                self.panel.orderOut(nil)
                self.shownSessionID = nil
                self.controller.panelHideAnimationCompleted(sessionID: capturedSession)
            }
        }
    }
}
