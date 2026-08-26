import XCTest

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testMigratesLegacyModifierAndPreservesUserChoices() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("option", forKey: "modifierKey")
        defaults.set(false, forKey: "translationEnabled")
        defaults.set("zh-to-en", forKey: "translationMode")
        defaults.set(0.2, forKey: "hoverDelay")
        defaults.set(true, forKey: "aiEnabled")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.triggerModifier, .leftOption)
        XCTAssertFalse(preferences.translationEnabled)
        XCTAssertEqual(preferences.direction, .chineseToEnglish)
        XCTAssertEqual(preferences.hoverDelay, 0.2)
        XCTAssertTrue(preferences.aiEnabled)
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

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "PointransTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }
}
