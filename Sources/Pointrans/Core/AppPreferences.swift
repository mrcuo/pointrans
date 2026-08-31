import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let translationEnabled = "translationEnabled"
        static let hoverDelay = "hoverDelay"
        static let didMigrateToV2 = "didMigrateToV2"
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let onboardingVersion = "onboardingVersion"
        static let onboardingStage = "onboardingStage"
        static let cloudContextConsent = "cloudContextConsent"

        static let removedKeys = [
            "deepseekApiKey",
            "deepseekEndpoint",
            "aiProvider",
            "aiModel",
            "customEndpoint",
            "modifierKey",
            "translationMode",
            "aiEnabled"
        ]
    }

    private let defaults: UserDefaults
    private var isLoading = true

    var translationEnabled: Bool { didSet { persist(Key.translationEnabled, translationEnabled) } }
    var hoverDelay: Double { didSet { persist(Key.hoverDelay, normalizedDelay(hoverDelay)) } }
    var onboardingVersion: Int { didSet { persist(Key.onboardingVersion, onboardingVersion) } }
    var onboardingStage: OnboardingStage { didSet { persist(Key.onboardingStage, onboardingStage.rawValue) } }
    var cloudContextConsent: CloudContextConsent {
        didSet { persist(Key.cloudContextConsent, cloudContextConsent.rawValue) }
    }

    var didCompleteOnboarding: Bool {
        get { onboardingVersion >= Self.currentOnboardingVersion }
        set {
            onboardingVersion = newValue ? Self.currentOnboardingVersion : 0
            if newValue { onboardingStage = .complete }
        }
    }

    private static let legacyOnboardingVersion = 1
    static let currentOnboardingVersion = 3

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyValues(in: defaults)

        translationEnabled = defaults.object(forKey: Key.translationEnabled) as? Bool ?? true
        hoverDelay = Self.clampedDelay(defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.25)
        let legacyComplete = defaults.bool(forKey: Key.didCompleteOnboarding)
        onboardingVersion = defaults.object(forKey: Key.onboardingVersion) as? Int
            ?? (legacyComplete ? Self.legacyOnboardingVersion : 0)
        let persistedStage = defaults.string(forKey: Key.onboardingStage) ?? ""
        // Version 2 exposed cloud routing as a standalone onboarding page.
        // Version 3 asks only at the exact moment an online explanation is
        // needed, so an interrupted legacy privacy page resumes in practice.
        onboardingStage = persistedStage == "privacy"
            ? .guidedExperience
            : OnboardingStage(rawValue: persistedStage) ?? (legacyComplete ? .complete : .welcome)
        cloudContextConsent = CloudContextConsent(
            rawValue: defaults.string(forKey: Key.cloudContextConsent) ?? ""
        ) ?? .undecided
        isLoading = false
    }

    private func persist(_ key: String, _ value: Any) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    private func normalizedDelay(_ value: Double) -> Double {
        let value = Self.clampedDelay(value)
        if value != hoverDelay {
            Task { @MainActor [weak self] in self?.hoverDelay = value }
        }
        return value
    }

    private static func clampedDelay(_ value: Double) -> Double {
        min(max(value, 0.15), 1.0)
    }

    static func migrateLegacyValues(in defaults: UserDefaults) {
        for key in Key.removedKeys {
            defaults.removeObject(forKey: key)
        }

        guard !defaults.bool(forKey: Key.didMigrateToV2) else { return }

        if let delay = defaults.object(forKey: Key.hoverDelay) as? Double {
            defaults.set(clampedDelay(delay), forKey: Key.hoverDelay)
        }
        defaults.set(true, forKey: Key.didMigrateToV2)
    }
}
