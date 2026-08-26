import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let translationEnabled = "translationEnabled"
        static let modifierKey = "modifierKey"
        static let hoverDelay = "hoverDelay"
        static let translationMode = "translationMode"
        static let aiEnabled = "aiEnabled"
        static let didMigrateToV2 = "didMigrateToV2"
        static let didCompleteOnboarding = "didCompleteOnboarding"

        static let removedKeys = [
            "deepseekApiKey",
            "deepseekEndpoint",
            "aiProvider",
            "aiModel",
            "customEndpoint"
        ]
    }

    private let defaults: UserDefaults
    private var isLoading = true

    var translationEnabled: Bool { didSet { persist(Key.translationEnabled, translationEnabled) } }
    var triggerModifier: TriggerModifier { didSet { persist(Key.modifierKey, triggerModifier.rawValue) } }
    var hoverDelay: Double { didSet { persist(Key.hoverDelay, normalizedDelay(hoverDelay)) } }
    var direction: TranslationDirection { didSet { persist(Key.translationMode, direction.rawValue) } }
    var aiEnabled: Bool { didSet { persist(Key.aiEnabled, aiEnabled) } }
    var didCompleteOnboarding: Bool { didSet { persist(Key.didCompleteOnboarding, didCompleteOnboarding) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyValues(in: defaults)

        translationEnabled = defaults.object(forKey: Key.translationEnabled) as? Bool ?? true
        triggerModifier = Self.migratedModifier(defaults.string(forKey: Key.modifierKey))
        hoverDelay = Self.clampedDelay(defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.25)
        direction = TranslationDirection(rawValue: defaults.string(forKey: Key.translationMode) ?? "")
            ?? Self.defaultDirection
        aiEnabled = defaults.object(forKey: Key.aiEnabled) as? Bool ?? true
        didCompleteOnboarding = defaults.bool(forKey: Key.didCompleteOnboarding)
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

    private static var defaultDirection: TranslationDirection {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .englishToChinese : .chineseToEnglish
    }

    private static func clampedDelay(_ value: Double) -> Double {
        min(max(value, 0.15), 1.0)
    }

    private static func migratedModifier(_ raw: String?) -> TriggerModifier {
        if let raw, let exact = TriggerModifier(rawValue: raw) { return exact }
        return switch raw?.lowercased() {
        case "command": .leftCommand
        case "control": .leftControl
        case "shift": .leftShift
        default: .leftOption
        }
    }

    static func migrateLegacyValues(in defaults: UserDefaults) {
        for key in Key.removedKeys {
            defaults.removeObject(forKey: key)
        }

        guard !defaults.bool(forKey: Key.didMigrateToV2) else { return }

        if let oldModifier = defaults.string(forKey: Key.modifierKey) {
            defaults.set(migratedModifier(oldModifier).rawValue, forKey: Key.modifierKey)
        }
        if defaults.object(forKey: Key.aiEnabled) == nil {
            defaults.set(true, forKey: Key.aiEnabled)
        }
        if let delay = defaults.object(forKey: Key.hoverDelay) as? Double {
            defaults.set(clampedDelay(delay), forKey: Key.hoverDelay)
        }
        defaults.set(true, forKey: Key.didMigrateToV2)
    }
}
