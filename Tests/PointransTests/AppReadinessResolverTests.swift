import XCTest

final class AppReadinessResolverTests: XCTestCase {
    func testOnboardingAndEveryRequiredPermissionOverrideRuntimeState() {
        XCTAssertEqual(resolve(onboardingComplete: false), .onboarding)
        XCTAssertEqual(resolve(accessibilityGranted: false), .needsAccessibility)
        XCTAssertEqual(resolve(screenCaptureGranted: false), .needsScreenCapture)
    }

    func testLanguagePreparationAndListenerRecoveryHaveDistinctStates() {
        XCTAssertEqual(resolve(languagePackStatus: .preparing), .preparingLanguagePack)
        XCTAssertEqual(resolve(triggerRuntimeState: .recovering), .recoveringListener)
        XCTAssertEqual(resolve(triggerRuntimeState: .failed), .listenerFailed)
        XCTAssertEqual(resolve(), .ready)
    }

    func testPauseOverridesCapabilityAndListenerState() {
        XCTAssertEqual(resolve(
            translationEnabled: false,
            accessibilityGranted: false,
            screenCaptureGranted: false,
            languagePackStatus: .preparing,
            triggerRuntimeState: .failed
        ), .paused)
    }

    private func resolve(
        onboardingComplete: Bool = true,
        translationEnabled: Bool = true,
        accessibilityGranted: Bool = true,
        screenCaptureGranted: Bool = true,
        languagePackStatus: LanguagePackStatus = .installed,
        triggerRuntimeState: TriggerRuntimeState = .active
    ) -> AppReadiness {
        AppReadinessResolver.resolve(
            onboardingComplete: onboardingComplete,
            translationEnabled: translationEnabled,
            accessibilityGranted: accessibilityGranted,
            screenCaptureGranted: screenCaptureGranted,
            languagePackStatus: languagePackStatus,
            triggerRuntimeState: triggerRuntimeState
        )
    }
}
