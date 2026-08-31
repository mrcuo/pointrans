import XCTest

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testMigrationRemovesRetiredConfigurationAndPreservesSupportedChoices() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("option", forKey: "modifierKey")
        defaults.set(false, forKey: "translationEnabled")
        defaults.set("zh-to-en", forKey: "translationMode")
        defaults.set(0.2, forKey: "hoverDelay")
        defaults.set(true, forKey: "aiEnabled")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertFalse(preferences.translationEnabled)
        XCTAssertEqual(preferences.hoverDelay, 0.2)
        XCTAssertNil(defaults.object(forKey: "modifierKey"))
        XCTAssertNil(defaults.object(forKey: "translationMode"))
        XCTAssertNil(defaults.object(forKey: "aiEnabled"))
    }

    func testDeletesLegacySecretsAndEndpoint() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let removedKeys = [
            "deepseekApiKey",
            "deepseekEndpoint",
            "aiProvider",
            "aiModel",
            "customEndpoint"
        ]
        for key in removedKeys {
            defaults.set("legacy-value", forKey: key)
        }
        _ = AppPreferences(defaults: defaults)
        for key in removedKeys {
            XCTAssertNil(defaults.object(forKey: key), "Expected \(key) to be deleted")
        }
    }

    func testClampsOutOfRangeDelay() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(4.0, forKey: "hoverDelay")
        XCTAssertEqual(AppPreferences(defaults: defaults).hoverDelay, 1.0)
    }

    func testOnboardingIsVersionedAndResumesAtPersistedStage() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(OnboardingStage.screenCapture.rawValue, forKey: "onboardingStage")
        defaults.set(CloudContextConsent.denied.rawValue, forKey: "cloudContextConsent")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertFalse(preferences.didCompleteOnboarding)
        XCTAssertEqual(preferences.onboardingStage, .screenCapture)
        XCTAssertEqual(preferences.cloudContextConsent, .denied)

        preferences.didCompleteOnboarding = true
        XCTAssertEqual(preferences.onboardingVersion, AppPreferences.currentOnboardingVersion)
        XCTAssertEqual(preferences.onboardingStage, .complete)
    }

    func testLegacyOnboardingDoesNotBypassTheNewMandatoryExperience() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "didCompleteOnboarding")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertFalse(preferences.didCompleteOnboarding)
        XCTAssertLessThan(preferences.onboardingVersion, AppPreferences.currentOnboardingVersion)
    }

    func testLegacyPrivacyPageResumesInTheIntegratedGuidedExperience() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("privacy", forKey: "onboardingStage")
        defaults.set(2, forKey: "onboardingVersion")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertFalse(preferences.didCompleteOnboarding)
        XCTAssertEqual(preferences.onboardingStage, .guidedExperience)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "PointransTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
}
