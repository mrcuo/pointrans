import XCTest

@MainActor
final class ApplicationLifetimeTests: XCTestCase {
    func testDelegateRemainsAliveForLifetimeOwner() {
        var lifetime: ApplicationLifetime<DelegateProbe>? = ApplicationLifetime(delegate: DelegateProbe())
        weak var delegate = lifetime?.delegate

        XCTAssertNotNil(delegate)

        lifetime = nil
        XCTAssertNil(delegate)
    }
}

private final class DelegateProbe {}
