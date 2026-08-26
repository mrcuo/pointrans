import CoreGraphics
import XCTest

final class SafeCorridorTests: XCTestCase {
    func testCorridorConnectsAnchorToPanelWithoutCoveringUnrelatedArea() {
        let corridor = SafeCorridor(
            anchor: CGPoint(x: 100, y: 100),
            target: CGRect(x: 140, y: 60, width: 360, height: 210),
            padding: 10
        )
        XCTAssertTrue(corridor.contains(CGPoint(x: 125, y: 95)))
        XCTAssertTrue(corridor.contains(CGPoint(x: 200, y: 100)))
        XCTAssertFalse(corridor.contains(CGPoint(x: 80, y: 300)))
    }
}
