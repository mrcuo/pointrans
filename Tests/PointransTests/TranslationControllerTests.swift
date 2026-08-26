import CoreGraphics
import XCTest

@MainActor
final class TranslationControllerTests: XCTestCase {
    func testNewHoverCancelsLateExtractionAndPublishesOnlyNewestSession() async throws {
        let points = testPoints()
        let harness = makeHarness(extractor: DelayedPointExtractor(splitX: (points.first.x + points.second.x) / 2, delayFirst: true))
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(180))
        harness.controller.receive(.pointerMoved(point: points.second, timestamp: 1.2))
        try await Task.sleep(for: .milliseconds(650))

        XCTAssertEqual(harness.controller.currentRequest?.word, "second")
        XCTAssertEqual(harness.controller.baseTranslation?.meanings, ["meaning-second"])
        guard case .preview(let sessionID) = harness.controller.panelMode else {
            return XCTFail("The newest session should own Preview")
        }
        XCTAssertEqual(sessionID, harness.controller.currentRequest?.id)
    }

    func testPinnedSessionRejectsNewHoverUntilClosed() async throws {
        let points = testPoints()
        let harness = makeHarness(extractor: DelayedPointExtractor(splitX: .infinity, delayFirst: false))
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(220))
        let originalID = try XCTUnwrap(harness.controller.currentRequest?.id)
        harness.controller.pinPanel()

        harness.controller.receive(.modifierPressed(point: points.second, timestamp: 2))
        try await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(harness.controller.currentRequest?.id, originalID)
        XCTAssertEqual(harness.controller.panelMode, .pinned(sessionID: originalID))
    }

    func testLateDeviceEnrichmentCannotOverwriteNewerBaseResult() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: DelayedPointExtractor(splitX: (points.first.x + points.second.x) / 2, delayFirst: false),
            translator: DelayedEnrichmentTranslator()
        )
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(230))
        harness.controller.receive(.pointerMoved(point: points.second, timestamp: 1.3))
        try await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(harness.controller.currentRequest?.word, "second")
        XCTAssertEqual(harness.controller.baseTranslation?.deviceTranslation, "device-second")
        XCTAssertFalse(harness.controller.baseTranslation?.meanings.contains("meaning-first") == true)
    }

    func testModifierReleaseWhileBaseTranslationIsPendingCannotOpenPreview() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: DelayedPointExtractor(splitX: .infinity, delayFirst: false),
            translator: CancellationIgnoringBaseTranslator()
        )
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(180))
        harness.controller.receive(.modifierReleased(point: points.first, timestamp: 1.2))
        try await Task.sleep(for: .milliseconds(450))

        XCTAssertEqual(harness.controller.panelMode, .hidden)
        XCTAssertNil(harness.controller.currentRequest)
        XCTAssertNil(harness.controller.baseTranslation)
    }

    func testTranslationFailureIsNotReportedAsExtractionFailure() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: DelayedPointExtractor(splitX: .infinity, delayFirst: false),
            translator: FailingBaseTranslator()
        )
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(260))

        guard case .failed(_, .translationUnavailable) = harness.controller.state else {
            return XCTFail("A base-translation failure must not trigger another extraction")
        }
        XCTAssertEqual(harness.controller.panelMode, .hidden)
    }

    func testReleasedPreviewMovementCannotArmAnotherTranslation() async throws {
        let points = testPoints()
        let extractor = CountingExtractor()
        let harness = makeHarness(extractor: extractor)
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        let countAfterPreview = await extractor.count
        XCTAssertEqual(countAfterPreview, 1)

        harness.controller.receive(.modifierReleased(point: points.first, timestamp: ProcessInfo.processInfo.systemUptime))
        harness.controller.receive(.pointerMoved(point: points.second, timestamp: ProcessInfo.processInfo.systemUptime + 0.1))
        try await Task.sleep(for: .milliseconds(300))

        let countAfterReleasedMovement = await extractor.count
        XCTAssertEqual(countAfterReleasedMovement, 1)
        XCTAssertEqual(harness.controller.panelMode, .hidden)
    }

    func testReleasedPreviewExpiresWhenPointerNeverEntersPanel() async throws {
        let points = testPoints()
        let harness = makeHarness(extractor: DelayedPointExtractor(splitX: .infinity, delayFirst: false))
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        harness.controller.updatePanelFrame(
            appKitFrame: ScreenCoordinates.quartzRectToAppKit(
                CGRect(x: points.first.x + 10, y: points.first.y + 10, width: 360, height: 210)
            )
        )
        harness.controller.receive(.modifierReleased(point: points.first, timestamp: ProcessInfo.processInfo.systemUptime))
        try await Task.sleep(for: .milliseconds(950))

        XCTAssertEqual(harness.controller.panelMode, .hidden)
    }

    func testDisablingAICancelsInsightAndRestoresBaseResult() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: DelayedPointExtractor(splitX: .infinity, delayFirst: false),
            analyzer: SlowAnalyzer()
        )
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        let requestID = try XCTUnwrap(harness.controller.currentRequest?.id)

        harness.controller.requestContextInsight()
        XCTAssertEqual(harness.controller.panelMode, .pinned(sessionID: requestID))
        guard case .enriching = harness.controller.state else {
            return XCTFail("AI request should enter the enriching state")
        }

        harness.controller.setAIEnabled(false)
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertFalse(harness.controller.preferences.aiEnabled)
        XCTAssertNil(harness.controller.insight)
        XCTAssertEqual(harness.controller.panelMode, .pinned(sessionID: requestID))
        guard case .ready(let readyID, let base, nil) = harness.controller.state else {
            return XCTFail("Turning AI off must preserve the base result")
        }
        XCTAssertEqual(readyID, requestID)
        XCTAssertEqual(base.meanings, ["meaning-first"])
    }

    func testOldPanelHideCompletionCannotClearANewerPreview() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: DelayedPointExtractor(
                splitX: (points.first.x + points.second.x) / 2,
                delayFirst: false
            )
        )
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        let oldID = try XCTUnwrap(harness.controller.currentRequest?.id)
        harness.controller.receive(.modifierReleased(point: points.first, timestamp: 1.3))

        harness.controller.receive(.modifierPressed(point: points.second, timestamp: 2))
        try await Task.sleep(for: .milliseconds(240))
        let newID = try XCTUnwrap(harness.controller.currentRequest?.id)
        XCTAssertNotEqual(oldID, newID)

        harness.controller.panelHideAnimationCompleted(sessionID: oldID)

        XCTAssertEqual(harness.controller.currentRequest?.id, newID)
        XCTAssertEqual(harness.controller.panelMode, .preview(sessionID: newID))
        XCTAssertEqual(harness.controller.baseTranslation?.meanings, ["meaning-second"])
    }

    private func testPoints() -> (first: CGPoint, second: CGPoint) {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let first = CGPoint(x: bounds.midX - 40, y: bounds.midY)
        return (first, CGPoint(x: first.x + 80, y: first.y))
    }

    private func makeHarness(
        extractor: any TextExtracting,
        translator: any BaseTranslating = ImmediateTranslator(),
        analyzer: any ContextAnalyzing = NoopAnalyzer()
    ) -> ControllerHarness {
        let suiteName = "PointransControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(0.15, forKey: "hoverDelay")
        defaults.set(TranslationDirection.englishToChinese.rawValue, forKey: "translationMode")
        let preferences = AppPreferences(defaults: defaults)
        let controller = TranslationController(
            preferences: preferences,
            environment: ProviderEnvironment(
                extractor: extractor,
                translator: translator,
                analyzer: analyzer,
                permissions: GrantedPermissions()
            )
        )
        return ControllerHarness(controller: controller, defaults: defaults, suiteName: suiteName)
    }
}

@MainActor
private struct ControllerHarness {
    let controller: TranslationController
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        controller.stop()
        controller.closePanel()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct DelayedPointExtractor: TextExtracting {
    let splitX: CGFloat
    let delayFirst: Bool

    func extract(at point: CGPoint, displayID: CGDirectDisplayID, direction: TranslationDirection) async throws -> ExtractionResult {
        let word = point.x < splitX ? "first" : "second"
        if word == "first" && delayFirst {
            // Simulate a provider that returns after cancellation; the controller must still reject it.
            try? await Task.sleep(for: .milliseconds(380))
        }
        return ExtractionResult(
            word: word,
            context: "context-\(word)",
            bounds: CGRect(x: point.x, y: point.y, width: 40, height: 18),
            confidence: 1,
            source: .accessibility
        )
    }
}

private struct ImmediateTranslator: BaseTranslating {
    func translate(word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation {
        BaseTranslation(meanings: ["meaning-\(word)"], deviceTranslation: nil, phonetic: nil, pinyin: nil, source: .dictionary)
    }
}

private struct DelayedEnrichmentTranslator: BaseTranslating {
    func translate(word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation {
        BaseTranslation(meanings: ["meaning-\(word)"], deviceTranslation: nil, phonetic: nil, pinyin: nil, source: .dictionary)
    }

    func enrich(_ base: BaseTranslation, word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation {
        if word == "first" {
            try? await Task.sleep(for: .milliseconds(420))
        }
        return BaseTranslation(
            meanings: base.meanings,
            deviceTranslation: "device-\(word)",
            phonetic: nil,
            pinyin: nil,
            source: .dictionaryAndApple
        )
    }
}

private struct CancellationIgnoringBaseTranslator: BaseTranslating {
    func translate(word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation {
        try? await Task.sleep(for: .milliseconds(320))
        return BaseTranslation(
            meanings: ["late-meaning"],
            deviceTranslation: nil,
            phonetic: nil,
            pinyin: nil,
            source: .dictionary
        )
    }
}

private struct FailingBaseTranslator: BaseTranslating {
    enum Failure: Error { case unavailable }

    func translate(word: String, context: String, direction: TranslationDirection) async throws -> BaseTranslation {
        throw Failure.unavailable
    }
}

private actor CountingExtractor: TextExtracting {
    private(set) var count = 0

    func extract(at point: CGPoint, displayID: CGDirectDisplayID, direction: TranslationDirection) async throws -> ExtractionResult {
        count += 1
        return ExtractionResult(
            word: "counted",
            context: "counted in context",
            bounds: CGRect(x: point.x, y: point.y, width: 40, height: 18),
            confidence: 1,
            source: .accessibility
        )
    }
}

private struct NoopAnalyzer: ContextAnalyzing {
    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> InsightResult {
        throw ContextAnalyzerError.unavailable
    }
}

private struct SlowAnalyzer: ContextAnalyzing {
    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> InsightResult {
        try? await Task.sleep(for: .milliseconds(300))
        return InsightResult(
            insight: ContextInsight(
                contextualMeaning: "late insight",
                partOfSpeech: nil,
                explanation: "must not be published",
                contextTranslation: nil
            ),
            route: .cloud,
            remainingCloudQuota: 29,
            quotaResetAt: nil
        )
    }
}

private struct GrantedPermissions: PermissionProviding {
    var accessibilityGranted: Bool { true }
    var screenCaptureGranted: Bool { true }
    func requestAccessibility() {}
    func requestScreenCapture() async -> Bool { true }
}
