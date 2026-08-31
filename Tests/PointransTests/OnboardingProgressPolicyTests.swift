import XCTest

final class OnboardingProgressPolicyTests: XCTestCase {
    func testWelcomeRequiresARealLeftOptionConfirmation() {
        XCTAssertFalse(OnboardingProgressPolicy.canAdvance(
            from: .welcome,
            accessibilityGranted: true,
            screenCaptureGranted: true,
            languagePackReady: true
        ))
        XCTAssertTrue(OnboardingProgressPolicy.canAdvance(
            from: .welcome,
            accessibilityGranted: true,
            screenCaptureGranted: true,
            languagePackReady: true,
            welcomeTriggerConfirmed: true
        ))
    }

    func testEveryRequiredCapabilityIsAHardGate() {
        XCTAssertFalse(OnboardingProgressPolicy.canAdvance(
            from: .accessibility,
            accessibilityGranted: false,
            screenCaptureGranted: true,
            languagePackReady: true
        ))
        XCTAssertFalse(OnboardingProgressPolicy.canAdvance(
            from: .screenCapture,
            accessibilityGranted: true,
            screenCaptureGranted: false,
            languagePackReady: true
        ))
        XCTAssertFalse(OnboardingProgressPolicy.canAdvance(
            from: .languagePack,
            accessibilityGranted: true,
            screenCaptureGranted: true,
            languagePackReady: false
        ))
        XCTAssertTrue(OnboardingProgressPolicy.canAdvance(
            from: .languagePack,
            accessibilityGranted: true,
            screenCaptureGranted: true,
            languagePackReady: true
        ))
    }

    func testGuidedExperienceRequiresTheExactTargetAndTwoRealNonemptyResults() {
        let base = BaseTranslation(
            meanings: ["突破"],
            deviceTranslation: nil,
            phonetic: nil,
            pinyin: nil,
            source: .dictionary
        )
        let insight = InsightResult(
            insight: ContextInsight(
                contextualMeaning: "取得重要进展",
                partOfSpeech: "noun",
                explanation: "这里表示长期努力后取得突破。",
                contextTranslation: nil
            ),
            route: .onDevice,
            remainingCloudQuota: nil,
            quotaResetAt: nil
        )

        XCTAssertFalse(OnboardingProgressPolicy.guidedExperienceIsComplete(
            word: "months",
            translation: base,
            insight: insight
        ))
        XCTAssertFalse(OnboardingProgressPolicy.guidedExperienceIsComplete(
            word: "breakthrough",
            translation: base,
            insight: nil
        ))
        XCTAssertTrue(OnboardingProgressPolicy.guidedExperienceIsComplete(
            word: "breakthrough",
            translation: base,
            insight: insight
        ))
        XCTAssertFalse(OnboardingProgressPolicy.canCompleteOnboarding(
            accessibilityGranted: true,
            screenCaptureGranted: false,
            languagePackReady: true,
            word: "breakthrough",
            translation: base,
            insight: insight
        ))
        XCTAssertFalse(OnboardingProgressPolicy.canCompleteOnboarding(
            accessibilityGranted: true,
            screenCaptureGranted: true,
            languagePackReady: false,
            word: "breakthrough",
            translation: base,
            insight: insight
        ))
        XCTAssertTrue(OnboardingProgressPolicy.canCompleteOnboarding(
            accessibilityGranted: true,
            screenCaptureGranted: true,
            languagePackReady: true,
            word: "breakthrough",
            translation: base,
            insight: insight
        ))
    }

    func testOnlineExplanationIsRequestedOnlyAtTheRecoverablePointOfNeed() {
        XCTAssertTrue(OnlineExplanationConsentPolicy.shouldPrompt(
            failure: .aiUnavailable,
            consent: .undecided
        ))
        XCTAssertFalse(OnlineExplanationConsentPolicy.shouldPrompt(
            failure: .aiUnavailable,
            consent: .denied
        ))
        XCTAssertFalse(OnlineExplanationConsentPolicy.shouldPrompt(
            failure: .aiUnavailable,
            consent: .allowed
        ))
        XCTAssertFalse(OnlineExplanationConsentPolicy.shouldPrompt(
            failure: .message("Safety refusal"),
            consent: .undecided
        ))
        XCTAssertFalse(OnlineExplanationConsentPolicy.shouldPrompt(
            failure: .onlineUnavailable,
            consent: .undecided
        ))
        XCTAssertFalse(OnlineExplanationConsentPolicy.shouldPrompt(
            failure: .onlineServiceIncompatible,
            consent: .undecided
        ))
    }
}
