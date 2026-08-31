import CoreGraphics
import Foundation

protocol TextExtracting: Sendable {
    func extract(at point: CGPoint, displayID: CGDirectDisplayID) async throws -> ExtractionResult
}

protocol BaseTranslating: Sendable {
    /// Resolves the device-AI → Apple Translation → dictionary route.
    func translate(request: TranslationRequest) async throws -> BaseTranslation
}

protocol ContextAnalyzing: Sendable {
    func analyze(
        request: TranslationRequest,
        base: BaseTranslation,
        allowsCloudFallback: Bool
    ) async throws -> InsightResult
}

protocol PermissionProviding: Sendable {
    var accessibilityGranted: Bool { get }
    var screenCaptureGranted: Bool { get }
    func requestAccessibility() async -> Bool
    func requestScreenCapture() async -> Bool
}

@MainActor
protocol EventMonitoring: AnyObject {
    var onEvent: ((TriggerEvent) -> Void)? { get set }
    var onAvailabilityChanged: ((Bool) -> Void)? { get set }
    func start() throws
    func stop()
    func setPreviewPointerTracking(_ enabled: Bool)
}

struct ProviderEnvironment: Sendable {
    let extractor: any TextExtracting
    let translator: any BaseTranslating
    let analyzer: any ContextAnalyzing
    let permissions: any PermissionProviding
}
