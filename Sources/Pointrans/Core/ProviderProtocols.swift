import CoreGraphics
import Foundation

protocol TextExtracting: Sendable {
    func extract(at point: CGPoint, displayID: CGDirectDisplayID, direction: TranslationDirection) async throws -> ExtractionResult
}

protocol BaseTranslating: Sendable {
    /// Fast indexed result. Implementations must not wait for network or language-pack work.
    func translate(word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation
    /// Optional device translation enrichment. The controller publishes the fast result first.
    func enrich(_ base: BaseTranslation, word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation
}

extension BaseTranslating {
    func enrich(_ base: BaseTranslation, word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation {
        base
    }
}

protocol ContextAnalyzing: Sendable {
    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> InsightResult
}

protocol PermissionProviding: Sendable {
    var accessibilityGranted: Bool { get }
    var screenCaptureGranted: Bool { get }
    func requestAccessibility()
    func requestScreenCapture() async -> Bool
}

struct ProviderEnvironment: Sendable {
    let extractor: any TextExtracting
    let translator: any BaseTranslating
    let analyzer: any ContextAnalyzing
    let permissions: any PermissionProviding
}
