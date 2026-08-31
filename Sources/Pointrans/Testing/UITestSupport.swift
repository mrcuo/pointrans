#if DEBUG
import CoreGraphics
import Foundation

enum UITestSupport {
    static let scenarioKey = "POINTRANS_UI_TEST_SCENARIO"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    static var scenario: String {
        ProcessInfo.processInfo.environment[scenarioKey] ?? "control-center"
    }

    static func environment() -> ProviderEnvironment {
        let permissionProvider = permissions()
        return ProviderEnvironment(
            extractor: FixtureExtractor(),
            translator: FixtureTranslator(),
            analyzer: FixtureAnalyzer(shouldFail: scenario == "ai-failure"),
            permissions: permissionProvider
        )
    }

    static func permissions() -> any PermissionProviding {
        FixturePermissions(granted: scenario != "permissions")
    }
}

private struct FixtureExtractor: TextExtracting {
    func extract(at point: CGPoint, displayID: CGDirectDisplayID) async throws -> ExtractionResult {
        ExtractionResult(
            word: "pulling",
            context: "She kept pulling the thread until the knot came loose.",
            bounds: CGRect(x: point.x - 20, y: point.y - 8, width: 48, height: 18),
            confidence: 1,
            source: .accessibility,
            detectedLanguage: .english
        )
    }
}

private struct FixtureTranslator: BaseTranslating {
    func translate(request: TranslationRequest) async throws -> BaseTranslation {
        BaseTranslation(
            meanings: ["拉动", "牵引", "抽出"],
            deviceTranslation: "拉动",
            phonetic: "/ˈpʊlɪŋ/",
            pinyin: nil,
            source: .deviceAI
        )
    }
}

private struct FixtureAnalyzer: ContextAnalyzing {
    let shouldFail: Bool

    func analyze(
        request: TranslationRequest,
        base: BaseTranslation,
        allowsCloudFallback: Bool
    ) async throws -> InsightResult {
        // Keep the loading state visible long enough for deterministic UI
        // verification without changing production timing.
        try await Task.sleep(for: .milliseconds(500))
        if shouldFail { throw ContextAnalyzerError.transient }
        return InsightResult(
            insight: ContextInsight(
                contextualMeaning: "持续拉扯",
                partOfSpeech: "verb",
                explanation: "这里表示用手持续施力，把线向自己的方向移动。",
                contextTranslation: "她不断拉扯那根线，直到结松开。"
            ),
            route: .onDevice,
            remainingCloudQuota: nil,
            quotaResetAt: nil
        )
    }
}

private struct FixturePermissions: PermissionProviding {
    let granted: Bool
    var accessibilityGranted: Bool { granted }
    var screenCaptureGranted: Bool { granted }
    func requestAccessibility() async -> Bool { granted }
    func requestScreenCapture() async -> Bool { granted }
}
#endif
