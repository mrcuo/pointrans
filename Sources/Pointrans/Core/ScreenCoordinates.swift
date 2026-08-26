import AppKit
import CoreGraphics

enum ScreenCoordinates {
    struct VerticalSpace: Equatable, Sendable {
        let appKitReferenceTop: CGFloat
        let quartzReferenceTop: CGFloat

        var conversionConstant: CGFloat { appKitReferenceTop + quartzReferenceTop }

        func appKitToQuartz(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: conversionConstant - point.y)
        }

        func quartzToAppKit(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: conversionConstant - point.y)
        }

        func appKitRectToQuartz(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: conversionConstant - rect.maxY, width: rect.width, height: rect.height)
        }

        func quartzRectToAppKit(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: conversionConstant - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    /// AppKit uses a bottom-left origin; Core Graphics event/AX APIs use the global top-left origin.
    static func appKitToQuartz(_ point: CGPoint, screens: [NSScreen] = NSScreen.screens) -> CGPoint {
        verticalSpace(screens: screens)?.appKitToQuartz(point) ?? point
    }

    static func quartzToAppKit(_ point: CGPoint, screens: [NSScreen] = NSScreen.screens) -> CGPoint {
        verticalSpace(screens: screens)?.quartzToAppKit(point) ?? point
    }

    static func appKitRectToQuartz(_ rect: CGRect, screens: [NSScreen] = NSScreen.screens) -> CGRect {
        verticalSpace(screens: screens)?.appKitRectToQuartz(rect) ?? rect
    }

    static func quartzRectToAppKit(_ rect: CGRect, screens: [NSScreen] = NSScreen.screens) -> CGRect {
        verticalSpace(screens: screens)?.quartzRectToAppKit(rect) ?? rect
    }

    static func displayID(containingAppKitPoint point: CGPoint, screens: [NSScreen] = NSScreen.screens) -> CGDirectDisplayID? {
        screens.first(where: { $0.frame.contains(point) })?.displayID
    }

    static func screen(for displayID: CGDirectDisplayID, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first(where: { $0.displayID == displayID })
    }

    static func stablePanelOrigin(
        anchor: CGPoint,
        panelSize: CGSize,
        screen: NSScreen,
        gap: CGFloat = 12
    ) -> CGPoint {
        stablePanelOrigin(anchor: anchor, panelSize: panelSize, visibleFrame: screen.visibleFrame, gap: gap)
    }

    static func stablePanelOrigin(
        anchor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 12
    ) -> CGPoint {
        let safe = visibleFrame.insetBy(dx: gap, dy: gap)
        let maximumX = max(safe.minX, safe.maxX - panelSize.width)
        let maximumY = max(safe.minY, safe.maxY - panelSize.height)

        let right = anchor.x + gap
        let left = anchor.x - gap - panelSize.width
        let x: CGFloat
        if right <= maximumX {
            x = max(right, safe.minX)
        } else if left >= safe.minX {
            x = min(left, maximumX)
        } else {
            x = min(max(right, safe.minX), maximumX)
        }

        let below = anchor.y - gap - panelSize.height
        let above = anchor.y + gap
        let y: CGFloat
        if below >= safe.minY {
            y = min(below, maximumY)
        } else if above <= maximumY {
            y = max(above, safe.minY)
        } else {
            y = min(max(below, safe.minY), maximumY)
        }
        return CGPoint(x: x, y: y)
    }

    private static func verticalSpace(screens: [NSScreen]) -> VerticalSpace? {
        let primaryID = CGMainDisplayID()
        guard let primary = screens.first(where: { $0.displayID == primaryID }) ?? screens.first else { return nil }
        let quartzTop = CGDisplayBounds(primary.displayID ?? primaryID).minY
        return VerticalSpace(appKitReferenceTop: primary.frame.maxY, quartzReferenceTop: quartzTop)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
