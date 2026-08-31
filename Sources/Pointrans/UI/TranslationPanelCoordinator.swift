import AppKit
import SwiftUI

@MainActor
private final class TranslationPanelWindow: NSPanel {
    var permitsKey = false
    var onCancel: (() -> Void)?
    var onCopyWithoutSelection: (() -> Void)?
    override var canBecomeKey: Bool { permitsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            if let textView = firstResponder as? NSTextView,
               textView.selectedRange().length > 0 {
                return super.performKeyEquivalent(with: event)
            }
            onCopyWithoutSelection?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class TranslationPanelMoveLimiter: NSObject, NSWindowDelegate {
    weak var controller: TranslationController?
    private var isAdjusting = false

    init(controller: TranslationController) {
        self.controller = controller
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAdjusting,
              controller?.panelMode.isPinned == true,
              let displayID = controller?.currentRequest?.displayID,
              let window = notification.object as? NSWindow,
              let screen = ScreenCoordinates.screen(for: displayID) else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var origin = window.frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - window.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - window.frame.height)
        guard origin != window.frame.origin else { return }
        isAdjusting = true
        window.setFrameOrigin(origin)
        isAdjusting = false
    }
}

@MainActor
final class TranslationPanelCoordinator {
    private let controller: TranslationController
    private let panel: TranslationPanelWindow
    private let hostingController: NSHostingController<TranslationCardView>
    private let moveLimiter: TranslationPanelMoveLimiter
    private let isUITesting: Bool
    private var shownSessionID: UUID?

    init(controller: TranslationController, isUITesting: Bool = false) {
        self.controller = controller
        self.isUITesting = isUITesting
        moveLimiter = TranslationPanelMoveLimiter(controller: controller)
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
        panel.onCancel = { [weak controller] in controller?.closePanel() }
        panel.onCopyWithoutSelection = { [weak controller] in
            guard let controller else { return }
            var pieces: [String] = []
            if let word = controller.currentRequest?.word { pieces.append(word) }
            if let base = controller.baseTranslation { pieces.append(base.primaryText) }
            if let insight = controller.insight?.insight {
                pieces.append(insight.contextualMeaning)
                pieces.append(insight.explanation)
                if let contextTranslation = insight.contextTranslation { pieces.append(contextTranslation) }
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(pieces.filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string)
        }
        panel.delegate = moveLimiter

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
        // Preview contains pronunciation and context controls. It remains a
        // non-activating panel, but must be eligible for key delivery on click.
        panel.permitsKey = true
        panel.isMovableByWindowBackground = pinned
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
