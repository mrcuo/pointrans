import XCTest

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
    func testScreenCaptureAcceptedButNotUsableRequiresRestart() async throws {
        let coordinator = PermissionCoordinator(provider: RestartRequiredPermissions())
        coordinator.refresh()
        coordinator.requestScreenCapture()

        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(coordinator.screenCapture, .restartRequired)
        XCTAssertFalse(coordinator.screenCaptureGranted)
    }
}

private struct RestartRequiredPermissions: PermissionProviding {
    var accessibilityGranted: Bool { true }
    var screenCaptureGranted: Bool { false }
    func requestAccessibility() async -> Bool { true }
    func requestScreenCapture() async -> Bool { true }
}
