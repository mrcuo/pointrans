import AppKit
import SwiftUI

@MainActor
final class StatusItemCoordinator: NSObject, NSPopoverDelegate {
    private let controller: TranslationController
    private let languagePacks: LanguagePackManager
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var testWindow: NSWindow?

    init(controller: TranslationController, languagePacks: LanguagePackManager) {
        self.controller = controller
        self.languagePacks = languagePacks
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = Self.makeTemplateIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Pointrans"
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("pointrans-menu-bar-button")
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ControlCenterView(controller: controller, languagePacks: languagePacks)
        )
        popover.contentSize = NSSize(width: 360, height: 520)
    }

    func show() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    #if DEBUG
    func showForUITesting() {
        if let testWindow {
            testWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Pointrans"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: ControlCenterView(controller: controller, languagePacks: languagePacks)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        testWindow = window
    }
    #endif

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    private static func makeTemplateIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let graphics = NSGraphicsContext.current else { return false }
            NSColor.black.setFill()

            let badge = NSBezierPath(
                roundedRect: NSRect(x: 1, y: 1.5, width: 15.5, height: 15.5),
                xRadius: 4,
                yRadius: 4
            )
            badge.fill()

            graphics.cgContext.saveGState()
            graphics.cgContext.setBlendMode(.clear)
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let p = NSBezierPath()
            p.lineWidth = 1.65
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to: NSPoint(x: 4.7, y: 4.4))
            p.line(to: NSPoint(x: 4.7, y: 14.1))
            p.line(to: NSPoint(x: 8.3, y: 14.1))
            p.curve(to: NSPoint(x: 11.7, y: 10.9), controlPoint1: NSPoint(x: 10.4, y: 14.1), controlPoint2: NSPoint(x: 11.7, y: 12.8))
            p.curve(to: NSPoint(x: 8.3, y: 8), controlPoint1: NSPoint(x: 11.7, y: 9.1), controlPoint2: NSPoint(x: 10.4, y: 8))
            p.line(to: NSPoint(x: 6.7, y: 8))
            p.stroke()

            let cursor = NSBezierPath()
            cursor.move(to: NSPoint(x: 9.5, y: 8.6))
            cursor.line(to: NSPoint(x: 14.6, y: 4.2))
            cursor.line(to: NSPoint(x: 12.2, y: 4.3))
            cursor.line(to: NSPoint(x: 11.2, y: 2.1))
            cursor.close()
            cursor.fill()
            graphics.cgContext.restoreGState()

            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14.8, y: 0.3, width: 2.5, height: 2.5)).fill()
            return true
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Pointrans"
        return image
    }
}
