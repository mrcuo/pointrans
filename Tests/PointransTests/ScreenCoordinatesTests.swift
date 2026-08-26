import CoreGraphics
import XCTest

final class ScreenCoordinatesTests: XCTestCase {
    func testVerticalAndNegativeDisplayCoordinatesRoundTrip() {
        let space = ScreenCoordinates.VerticalSpace(appKitReferenceTop: 1080, quartzReferenceTop: 0)
        let points = [
            CGPoint(x: 120, y: 540),
            CGPoint(x: -1600, y: 400),
            CGPoint(x: 300, y: 1700),
            CGPoint(x: 2000, y: -400)
        ]
        for point in points {
            XCTAssertEqual(space.quartzToAppKit(space.appKitToQuartz(point)), point)
        }
    }

    func testRectConversionUsesTopEdgeAndPreservesRetinaPointSize() {
        let space = ScreenCoordinates.VerticalSpace(appKitReferenceTop: 1080, quartzReferenceTop: 0)
        let appKit = CGRect(x: -1440, y: 100, width: 360, height: 210)
        XCTAssertEqual(space.appKitRectToQuartz(appKit), CGRect(x: -1440, y: 770, width: 360, height: 210))
    }

    func testPanelOriginStaysInsideVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: 420, height: 480)
        let origin = ScreenCoordinates.stablePanelOrigin(
            anchor: CGPoint(x: 790, y: 20),
            panelSize: size,
            visibleFrame: visible
        )
        XCTAssertEqual(origin, CGPoint(x: 358, y: 32))
        XCTAssertTrue(visible.insetBy(dx: 12, dy: 12).contains(CGPoint(x: origin.x, y: origin.y)))
        XCTAssertLessThanOrEqual(origin.x + size.width, visible.maxX - 12)
        XCTAssertLessThanOrEqual(origin.y + size.height, visible.maxY - 12)
    }

    func testPanelUsesNegativeDisplayFrameWithoutJumpingToMainScreen() {
        let visible = CGRect(x: -1440, y: 80, width: 1440, height: 900)
        let origin = ScreenCoordinates.stablePanelOrigin(
            anchor: CGPoint(x: -30, y: 700),
            panelSize: CGSize(width: 360, height: 210),
            visibleFrame: visible
        )
        XCTAssertEqual(origin, CGPoint(x: -402, y: 478))
        XCTAssertGreaterThanOrEqual(origin.x, visible.minX + 12)
        XCTAssertLessThanOrEqual(origin.x + 360, visible.maxX - 12)
    }
}
