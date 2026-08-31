import CoreGraphics
import Foundation

enum TranslationDirection: String, Codable, CaseIterable, Sendable {
    case englishToChinese = "en-to-zh"
    case chineseToEnglish = "zh-to-en"

    var sourceLanguage: String {
        switch self {
        case .englishToChinese: "en"
        case .chineseToEnglish: "zh-Hans"
        }
    }

    var targetLanguage: String {
        switch self {
        case .englishToChinese: "zh-Hans"
        case .chineseToEnglish: "en"
        }
    }

    var localizedTitle: String {
        switch self {
        case .englishToChinese: String(localized: "English → Chinese")
        case .chineseToEnglish: String(localized: "Chinese → English")
        }
    }
}

enum DetectedLanguage: String, Codable, Sendable {
    case english
    case simplifiedChinese
    case unsupported

    var direction: TranslationDirection? {
        switch self {
        case .english: .englishToChinese
        case .simplifiedChinese: .chineseToEnglish
        case .unsupported: nil
        }
    }

    static func detect(_ value: String) -> DetectedLanguage {
        var latin = 0
        var han = 0
        for scalar in value.unicodeScalars {
            if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) {
                latin += 1
            } else if (0x3400...0x4DBF).contains(scalar.value) ||
                        (0x4E00...0x9FFF).contains(scalar.value) ||
                        (0x20000...0x2FA1F).contains(scalar.value) {
                han += 1
            }
        }
        guard latin > 0 || han > 0 else { return .unsupported }
        return han > latin ? .simplifiedChinese : .english
    }
}

struct TranslationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let screenPoint: CGPoint
    let displayID: CGDirectDisplayID
    let word: String
    let context: String
    let targetUTF16Range: NSRange?
    let direction: TranslationDirection
    let createdAt: Date

    init(
        id: UUID,
        screenPoint: CGPoint,
        displayID: CGDirectDisplayID,
        word: String,
        context: String,
        targetUTF16Range: NSRange? = nil,
        direction: TranslationDirection,
        createdAt: Date
    ) {
        self.id = id
        self.screenPoint = screenPoint
        self.displayID = displayID
        self.word = word
        self.context = context
        self.targetUTF16Range = targetUTF16Range
        self.direction = direction
        self.createdAt = createdAt
    }
}

enum ExtractionSource: String, Codable, Sendable {
    case accessibility
    case ocr
    case guidedSample
}

struct ExtractionResult: Equatable, Sendable {
    let word: String
    let context: String
    let targetUTF16Range: NSRange?
    let bounds: CGRect
    let confidence: Float
    let source: ExtractionSource
    let detectedLanguage: DetectedLanguage

    init(
        word: String,
        context: String,
        targetUTF16Range: NSRange? = nil,
        bounds: CGRect,
        confidence: Float,
        source: ExtractionSource,
        detectedLanguage: DetectedLanguage? = nil
    ) {
        self.word = word
        self.context = context
        self.targetUTF16Range = targetUTF16Range
        self.bounds = bounds
        self.confidence = confidence
        self.source = source
        self.detectedLanguage = detectedLanguage ?? .detect(word)
    }
}

enum ExtractionError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case screenCapturePermissionRequired
    case noTextAtPointer
    case unsupportedApplication
    case captureFailed
}

enum TranslationSource: String, Codable, Sendable {
    case deviceAI
    case dictionary
    case appleTranslation
}

enum TranslationRoute: String, Codable, Sendable {
    case deviceAI
    case appleTranslation
    case dictionary
}

struct BaseTranslation: Equatable, Sendable {
    let meanings: [String]
    let deviceTranslation: String?
    let phonetic: String?
    let pinyin: String?
    let source: TranslationSource

    var primaryText: String {
        if let deviceTranslation, !deviceTranslation.isEmpty { return deviceTranslation }
        return meanings.joined(separator: " · ")
    }
}

struct ContextInsight: Codable, Equatable, Sendable {
    let contextualMeaning: String
    let partOfSpeech: String?
    let explanation: String
    let contextTranslation: String?
}

enum InsightRoute: String, Codable, Sendable {
    case onDevice
    case cloud
}

enum CloudContextConsent: String, Codable, Sendable {
    case undecided
    case allowed
    case denied
}

enum PermissionState: Equatable, Sendable {
    case unknown
    case checking
    case notGranted
    case requesting
    case granted
    case denied
    case restartRequired
}

enum AppReadiness: Equatable, Sendable {
    case launching
    case onboarding
    case ready
    case paused
    case needsAccessibility
    case needsScreenCapture
    case preparingLanguagePack
    case recoveringListener
    case listenerFailed
    case fatalStartupError
}

enum AppReadinessResolver {
    static func resolve(
        onboardingComplete: Bool,
        translationEnabled: Bool,
        accessibilityGranted: Bool,
        screenCaptureGranted: Bool,
        languagePackStatus: LanguagePackStatus,
        triggerRuntimeState: TriggerRuntimeState
    ) -> AppReadiness {
        guard onboardingComplete else { return .onboarding }
        guard translationEnabled else { return .paused }
        guard accessibilityGranted else { return .needsAccessibility }
        guard screenCaptureGranted else { return .needsScreenCapture }
        if languagePackStatus == .checking || languagePackStatus == .preparing {
            return .preparingLanguagePack
        }
        return switch triggerRuntimeState {
        case .active: .ready
        case .starting, .recovering: .recoveringListener
        case .failed: .listenerFailed
        case .waitingForAccessibility: .needsAccessibility
        case .waitingForScreenCapture: .needsScreenCapture
        case .stopped: .paused
        }
    }
}

enum OnboardingStage: String, Codable, CaseIterable, Sendable {
    case welcome
    case accessibility
    case screenCapture
    case languagePack
    case guidedExperience
    case complete
}

enum OnboardingProgressPolicy {
    static let guidedTargetWord = "breakthrough"

    static func canAdvance(
        from stage: OnboardingStage,
        accessibilityGranted: Bool,
        screenCaptureGranted: Bool,
        languagePackReady: Bool,
        welcomeTriggerConfirmed: Bool = false
    ) -> Bool {
        switch stage {
        case .welcome: welcomeTriggerConfirmed
        case .accessibility: accessibilityGranted
        case .screenCapture: screenCaptureGranted
        case .languagePack: languagePackReady
        case .guidedExperience, .complete: false
        }
    }

    static func guidedExperienceIsComplete(
        word: String?,
        translation: BaseTranslation?,
        insight: InsightResult?
    ) -> Bool {
        word?.localizedCaseInsensitiveCompare(guidedTargetWord) == .orderedSame &&
            translation?.primaryText.isEmpty == false &&
            insight?.insight.contextualMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func canCompleteOnboarding(
        accessibilityGranted: Bool,
        screenCaptureGranted: Bool,
        languagePackReady: Bool,
        word: String?,
        translation: BaseTranslation?,
        insight: InsightResult?
    ) -> Bool {
        accessibilityGranted &&
            screenCaptureGranted &&
            languagePackReady &&
            guidedExperienceIsComplete(word: word, translation: translation, insight: insight)
    }
}

struct InsightResult: Equatable, Sendable {
    let insight: ContextInsight
    let route: InsightRoute
    let remainingCloudQuota: Int?
    let quotaResetAt: Date?
}

enum TranslationFailure: Error, Equatable, Sendable {
    case extractionUnavailable
    case noTextFound
    case translationUnavailable
    case aiUnavailable
    case onlineUnavailable
    case onlineServiceIncompatible
    case quotaExhausted(resetAt: Date?)
    case permissionRequired
    case cancelled
    case message(String)
}

enum OnlineExplanationConsentPolicy {
    static func shouldPrompt(failure: TranslationFailure, consent: CloudContextConsent) -> Bool {
        failure == .aiUnavailable && consent == .undecided
    }
}

enum TranslationState: Equatable, Sendable {
    case idle
    case extracting(requestID: UUID)
    case enriching(requestID: UUID, BaseTranslation)
    case ready(requestID: UUID, BaseTranslation, InsightResult?)
    case failed(requestID: UUID?, TranslationFailure)

    var requestID: UUID? {
        switch self {
        case .idle: nil
        case .extracting(let id), .enriching(let id, _),
             .ready(let id, _, _): id
        case .failed(let id, _): id
        }
    }
}

enum BaseTranslationPhase: Equatable, Sendable {
    case idle
    case extracting(requestID: UUID)
    case ready(requestID: UUID, BaseTranslation)
    case failed(requestID: UUID?, TranslationFailure)

    var requestID: UUID? {
        switch self {
        case .idle: nil
        case .extracting(let id), .ready(let id, _): id
        case .failed(let id, _): id
        }
    }

    var translation: BaseTranslation? {
        switch self {
        case .ready(_, let value): value
        case .idle, .extracting, .failed: nil
        }
    }
}

enum ContextInsightPhase: Equatable, Sendable {
    case idle
    case loading(requestID: UUID)
    case ready(requestID: UUID, InsightResult)
    case failed(requestID: UUID, TranslationFailure)

    var result: InsightResult? {
        if case .ready(_, let result) = self { return result }
        return nil
    }
}

enum TriggerRuntimeState: Equatable, Sendable {
    case stopped
    case waitingForAccessibility
    case waitingForScreenCapture
    case starting
    case active
    case recovering
    case failed
}

enum PanelMode: Equatable, Sendable {
    case hidden
    case preview(sessionID: UUID)
    case pinned(sessionID: UUID)

    var isPinned: Bool {
        if case .pinned = self { return true }
        return false
    }

    var isPreview: Bool {
        if case .preview = self { return true }
        return false
    }
}
