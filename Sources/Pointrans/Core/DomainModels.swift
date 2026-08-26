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

enum TriggerModifier: String, Codable, CaseIterable, Sendable {
    case leftOption = "option-l"
    case rightOption = "option-r"
    case leftCommand = "command-l"
    case rightCommand = "command-r"
    case leftControl = "control-l"
    case rightControl = "control-r"
    case leftShift = "shift-l"
    case rightShift = "shift-r"

    var localizedTitle: String {
        switch self {
        case .leftOption: String(localized: "Left Option (⌥)")
        case .rightOption: String(localized: "Right Option (⌥)")
        case .leftCommand: String(localized: "Left Command (⌘)")
        case .rightCommand: String(localized: "Right Command (⌘)")
        case .leftControl: String(localized: "Left Control (⌃)")
        case .rightControl: String(localized: "Right Control (⌃)")
        case .leftShift: String(localized: "Left Shift (⇧)")
        case .rightShift: String(localized: "Right Shift (⇧)")
        }
    }
}

struct TranslationRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let screenPoint: CGPoint
    let displayID: CGDirectDisplayID
    let word: String
    let context: String
    let direction: TranslationDirection
    let createdAt: Date
}

enum ExtractionSource: String, Codable, Sendable {
    case accessibility
    case ocr
}

struct ExtractionResult: Equatable, Sendable {
    let word: String
    let context: String
    let bounds: CGRect
    let confidence: Float
    let source: ExtractionSource
}

enum TranslationSource: String, Codable, Sendable {
    case dictionary
    case appleTranslation
    case dictionaryAndApple
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
    case quotaExhausted(resetAt: Date?)
    case permissionRequired
    case cancelled
    case message(String)
}

enum TranslationState: Equatable, Sendable {
    case idle
    case extracting(requestID: UUID)
    case baseReady(requestID: UUID, BaseTranslation)
    case enriching(requestID: UUID, BaseTranslation)
    case ready(requestID: UUID, BaseTranslation, InsightResult?)
    case failed(requestID: UUID?, TranslationFailure)

    var requestID: UUID? {
        switch self {
        case .idle: nil
        case .extracting(let id), .baseReady(let id, _), .enriching(let id, _),
             .ready(let id, _, _): id
        case .failed(let id, _): id
        }
    }
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
