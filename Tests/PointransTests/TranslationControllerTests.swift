import CoreGraphics
import XCTest

@MainActor
final class TranslationControllerTests: XCTestCase {
    func testNewHoverCancelsLateExtractionAndPublishesOnlyNewestSession() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: PointExtractor(
                splitX: (points.first.x + points.second.x) / 2,
                delaysFirstResult: true
            )
        )
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
        let harness = makeHarness(extractor: PointExtractor(splitX: .infinity))
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        let originalID = try XCTUnwrap(harness.controller.currentRequest?.id)
        harness.controller.pinPanel()

        harness.controller.receive(.modifierPressed(point: points.second, timestamp: 2))
        try await Task.sleep(for: .milliseconds(240))

        XCTAssertEqual(harness.controller.currentRequest?.id, originalID)
        XCTAssertEqual(harness.controller.panelMode, .pinned(sessionID: originalID))
    }

    func testModifierReleaseWhileTranslationIsPendingCannotOpenPreview() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: PointExtractor(splitX: .infinity),
            translator: CancellationIgnoringTranslator()
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

    func testTranslationFailureShowsBriefUnderstandableResultInsteadOfEmptyWindow() async throws {
        let points = testPoints()
        let harness = makeHarness(
            extractor: PointExtractor(splitX: .infinity),
            translator: FailingTranslator()
        )
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(260))

        guard case .failed(_, .translationUnavailable) = harness.controller.state else {
            return XCTFail("Translation errors must remain distinct from extraction failures")
        }
        guard case .preview = harness.controller.panelMode else {
            return XCTFail("A short error card should explain that all translation routes failed")
        }
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

        let now = ProcessInfo.processInfo.systemUptime
        harness.controller.receive(.modifierReleased(point: points.first, timestamp: now))
        harness.controller.receive(.pointerMoved(point: points.second, timestamp: now + 0.1))
        try await Task.sleep(for: .milliseconds(300))

        let countAfterReleasedMovement = await extractor.count
        XCTAssertEqual(countAfterReleasedMovement, 1)
        XCTAssertEqual(harness.controller.panelMode, .hidden)
    }

    func testBothRequiredPermissionsGateTheListener() {
        let permissions = MutablePermissions(accessibility: false, screenCapture: false)
        let monitor = TestEventMonitor()
        let harness = makeHarness(
            extractor: PointExtractor(splitX: .infinity),
            permissions: permissions,
            monitor: monitor
        )
        defer { harness.cleanup() }

        harness.controller.start()
        XCTAssertEqual(harness.controller.triggerRuntimeState, .waitingForAccessibility)
        XCTAssertEqual(monitor.startCount, 0)

        permissions.update(accessibility: true)
        harness.controller.applicationDidBecomeActive()
        XCTAssertEqual(harness.controller.triggerRuntimeState, .waitingForScreenCapture)
        XCTAssertEqual(monitor.startCount, 0)

        permissions.update(screenCapture: true)
        harness.controller.applicationDidBecomeActive()
        XCTAssertEqual(harness.controller.triggerRuntimeState, .active)
        XCTAssertEqual(monitor.startCount, 1)
    }

    func testMonitorCreationFailureRecoversWithoutRelaunch() async throws {
        let monitor = TestEventMonitor(failuresBeforeSuccess: 1)
        let harness = makeHarness(
            extractor: PointExtractor(splitX: .infinity),
            monitor: monitor
        )
        defer { harness.cleanup() }

        harness.controller.start()
        XCTAssertEqual(harness.controller.triggerRuntimeState, .recovering)
        try await Task.sleep(for: .milliseconds(650))

        XCTAssertEqual(monitor.startCount, 2)
        XCTAssertEqual(harness.controller.triggerRuntimeState, .active)
    }

    func testContextRequestUsesPersistedCloudConsentAndPinsPreview() async throws {
        let points = testPoints()
        let analyzer = ConsentRecordingAnalyzer()
        let harness = makeHarness(extractor: PointExtractor(splitX: .infinity), analyzer: analyzer)
        defer { harness.cleanup() }
        harness.controller.preferences.cloudContextConsent = .denied

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        let requestID = try XCTUnwrap(harness.controller.currentRequest?.id)
        harness.controller.requestContextInsight()
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(harness.controller.panelMode, .pinned(sessionID: requestID))
        let deniedConsent = await analyzer.receivedConsent
        XCTAssertEqual(deniedConsent, false)

        harness.controller.closePanel()
        harness.controller.preferences.cloudContextConsent = .allowed
        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 2))
        try await Task.sleep(for: .milliseconds(240))
        harness.controller.requestContextInsight()
        try await Task.sleep(for: .milliseconds(80))
        let allowedConsent = await analyzer.receivedConsent
        XCTAssertEqual(allowedConsent, true)

        harness.controller.requestContextInsight(allowsOnlineFallback: false)
        try await Task.sleep(for: .milliseconds(80))
        let forcedDeviceOnly = await analyzer.receivedConsent
        XCTAssertEqual(forcedDeviceOnly, false)
        XCTAssertEqual(harness.controller.preferences.cloudContextConsent, .allowed)
    }

    func testOnlineContextFailuresRemainDistinctFromDeviceAvailability() async throws {
        let points = testPoints()
        for (error, expected) in [
            (ContextAnalyzerError.onlineUnavailable, TranslationFailure.onlineUnavailable),
            (ContextAnalyzerError.onlineServiceIncompatible, TranslationFailure.onlineServiceIncompatible)
        ] {
            let harness = makeHarness(
                extractor: PointExtractor(splitX: .infinity),
                analyzer: SpecificFailingAnalyzer(error: error)
            )
            defer { harness.cleanup() }

            harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
            try await Task.sleep(for: .milliseconds(240))
            harness.controller.requestContextInsight()
            try await Task.sleep(for: .milliseconds(80))

            guard case .failed(_, let failure) = harness.controller.insightPhase else {
                return XCTFail("Expected a distinct online failure")
            }
            XCTAssertEqual(failure, expected)
        }
    }

    func testClosingPinnedResultCancelsOutstandingContextTask() async throws {
        let points = testPoints()
        let analyzer = SlowCancellableAnalyzer()
        let harness = makeHarness(extractor: PointExtractor(splitX: .infinity), analyzer: analyzer)
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        harness.controller.requestContextInsight()
        harness.controller.closePanel()
        try await Task.sleep(for: .milliseconds(80))

        let wasCancelled = await analyzer.wasCancelled
        XCTAssertTrue(wasCancelled)
        XCTAssertNil(harness.controller.insight)
        XCTAssertEqual(harness.controller.panelMode, .hidden)
    }

    func testRevokingCloudConsentCancelsARequestThatCouldStillFallback() async throws {
        let points = testPoints()
        let analyzer = SlowCancellableAnalyzer()
        let harness = makeHarness(extractor: PointExtractor(splitX: .infinity), analyzer: analyzer)
        defer { harness.cleanup() }
        harness.controller.setCloudContextConsent(.allowed)

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        harness.controller.requestContextInsight()
        try await Task.sleep(for: .milliseconds(20))
        harness.controller.setCloudContextConsent(.denied)
        try await Task.sleep(for: .milliseconds(80))

        let wasCancelled = await analyzer.wasCancelled
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(harness.controller.preferences.cloudContextConsent, .denied)
        XCTAssertNotNil(harness.controller.baseTranslation)
        XCTAssertNil(harness.controller.insight)
    }

    func testDetectedScriptDeterminesDirectionWithoutASetting() async throws {
        let points = testPoints()
        let translator = RequestRecordingTranslator()
        let harness = makeHarness(
            extractor: LiteralExtractor(word: "翻译", context: "这个词需要翻译"),
            translator: translator
        )
        defer { harness.cleanup() }

        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))

        let direction = await translator.lastDirection
        XCTAssertEqual(direction, .chineseToEnglish)
    }

    func testGuidedExperienceUsesTheVisibleTargetAndTheRealPreviewCard() async throws {
        let points = testPoints()
        let extractor = CountingExtractor()
        let harness = makeHarness(extractor: extractor)
        defer { harness.cleanup() }
        let targetQuartz = CGRect(
            x: points.first.x - 40,
            y: points.first.y - 15,
            width: 80,
            height: 30
        )
        let sentence = "She finally made a breakthrough after months of work."

        harness.controller.setTutorialMode(true)
        harness.controller.updateTutorialTarget(
            appKitFrame: ScreenCoordinates.quartzRectToAppKit(targetQuartz),
            word: "breakthrough",
            context: sentence,
            targetUTF16Range: (sentence as NSString).range(of: "breakthrough")
        )
        harness.controller.receive(.modifierPressed(point: points.first, timestamp: 1))
        try await Task.sleep(for: .milliseconds(260))

        let extractionCount = await extractor.count
        XCTAssertEqual(extractionCount, 0, "The visible built-in sample should not depend on AX or OCR")
        XCTAssertEqual(harness.controller.currentRequest?.word, "breakthrough")
        XCTAssertEqual(harness.controller.extraction?.source, .guidedSample)
        XCTAssertNotNil(harness.controller.baseTranslation)
        guard case .preview(let sessionID) = harness.controller.panelMode else {
            return XCTFail("The guided result must use the same real Preview card as normal translation")
        }

        harness.controller.requestContextInsight(allowsOnlineFallback: false)
        XCTAssertEqual(harness.controller.panelMode, .pinned(sessionID: sessionID))

        harness.controller.completeTutorialModeKeepingResult()
        XCTAssertFalse(harness.controller.isTutorialMode)
        XCTAssertEqual(harness.controller.panelMode, .pinned(sessionID: sessionID))
        XCTAssertNotNil(harness.controller.baseTranslation)
    }

    private func testPoints() -> (first: CGPoint, second: CGPoint) {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let first = CGPoint(x: bounds.midX - 40, y: bounds.midY)
        return (first, CGPoint(x: first.x + 80, y: first.y))
    }

    private func makeHarness(
        extractor: any TextExtracting,
        translator: any BaseTranslating = ImmediateTranslator(),
        analyzer: any ContextAnalyzing = UnavailableAnalyzer(),
        permissions: any PermissionProviding = GrantedPermissions(),
        monitor: (any EventMonitoring)? = nil
    ) -> ControllerHarness {
        let suiteName = "PointransControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(0.15, forKey: "hoverDelay")
        let preferences = AppPreferences(defaults: defaults)
        let controller = TranslationController(
            preferences: preferences,
            environment: ProviderEnvironment(
                extractor: extractor,
                translator: translator,
                analyzer: analyzer,
                permissions: permissions
            ),
            monitor: monitor
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

private struct PointExtractor: TextExtracting {
    let splitX: CGFloat
    var delaysFirstResult = false

    func extract(at point: CGPoint, displayID: CGDirectDisplayID) async throws -> ExtractionResult {
        let word = point.x < splitX ? "first" : "second"
        if word == "first" && delaysFirstResult {
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

private struct LiteralExtractor: TextExtracting {
    let word: String
    let context: String

    func extract(at point: CGPoint, displayID: CGDirectDisplayID) async throws -> ExtractionResult {
        ExtractionResult(
            word: word,
            context: context,
            bounds: CGRect(x: point.x, y: point.y, width: 40, height: 18),
            confidence: 1,
            source: .accessibility
        )
    }
}

private actor CountingExtractor: TextExtracting {
    private(set) var count = 0

    func extract(at point: CGPoint, displayID: CGDirectDisplayID) async throws -> ExtractionResult {
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

private struct ImmediateTranslator: BaseTranslating {
    func translate(request: TranslationRequest) async throws -> BaseTranslation {
        BaseTranslation(
            meanings: ["meaning-\(request.word)"],
            deviceTranslation: nil,
            phonetic: nil,
            pinyin: nil,
            source: .dictionary
        )
    }
}

private struct CancellationIgnoringTranslator: BaseTranslating {
    func translate(request: TranslationRequest) async throws -> BaseTranslation {
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

private struct FailingTranslator: BaseTranslating {
    enum Failure: Error { case unavailable }
    func translate(request: TranslationRequest) async throws -> BaseTranslation { throw Failure.unavailable }
}

private actor RequestRecordingTranslator: BaseTranslating {
    private(set) var lastDirection: TranslationDirection?

    func translate(request: TranslationRequest) async throws -> BaseTranslation {
        lastDirection = request.direction
        return BaseTranslation(
            meanings: ["translation"],
            deviceTranslation: nil,
            phonetic: nil,
            pinyin: nil,
            source: .dictionary
        )
    }
}

private struct UnavailableAnalyzer: ContextAnalyzing {
    func analyze(
        request: TranslationRequest,
        base: BaseTranslation,
        allowsCloudFallback: Bool
    ) async throws -> InsightResult {
        throw ContextAnalyzerError.unavailable
    }
}

private struct SpecificFailingAnalyzer: ContextAnalyzing {
    let error: ContextAnalyzerError

    func analyze(
        request: TranslationRequest,
        base: BaseTranslation,
        allowsCloudFallback: Bool
    ) async throws -> InsightResult {
        throw error
    }
}

private actor ConsentRecordingAnalyzer: ContextAnalyzing {
    private(set) var receivedConsent: Bool?

    func analyze(
        request: TranslationRequest,
        base: BaseTranslation,
        allowsCloudFallback: Bool
    ) async throws -> InsightResult {
        receivedConsent = allowsCloudFallback
        return InsightResult(
            insight: ContextInsight(
                contextualMeaning: "context",
                partOfSpeech: nil,
                explanation: "explanation",
                contextTranslation: nil
            ),
            route: .onDevice,
            remainingCloudQuota: nil,
            quotaResetAt: nil
        )
    }
}

private actor SlowCancellableAnalyzer: ContextAnalyzing {
    private(set) var wasCancelled = false

    func analyze(
        request: TranslationRequest,
        base: BaseTranslation,
        allowsCloudFallback: Bool
    ) async throws -> InsightResult {
        do {
            try await Task.sleep(for: .seconds(2))
            throw ContextAnalyzerError.transient
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

private struct GrantedPermissions: PermissionProviding {
    var accessibilityGranted: Bool { true }
    var screenCaptureGranted: Bool { true }
    func requestAccessibility() async -> Bool { true }
    func requestScreenCapture() async -> Bool { true }
}

private final class MutablePermissions: PermissionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var accessibility: Bool
    private var screenCapture: Bool

    init(accessibility: Bool, screenCapture: Bool) {
        self.accessibility = accessibility
        self.screenCapture = screenCapture
    }

    var accessibilityGranted: Bool { lock.withLock { accessibility } }
    var screenCaptureGranted: Bool { lock.withLock { screenCapture } }

    func update(accessibility: Bool? = nil, screenCapture: Bool? = nil) {
        lock.withLock {
            if let accessibility { self.accessibility = accessibility }
            if let screenCapture { self.screenCapture = screenCapture }
        }
    }

    func requestAccessibility() async -> Bool { accessibilityGranted }
    func requestScreenCapture() async -> Bool { screenCaptureGranted }
}

@MainActor
private final class TestEventMonitor: EventMonitoring {
    enum Failure: Error { case unavailable }

    var onEvent: ((TriggerEvent) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    private(set) var startCount = 0
    private var failuresBeforeSuccess: Int

    init(failuresBeforeSuccess: Int = 0) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func start() throws {
        startCount += 1
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            onAvailabilityChanged?(false)
            throw Failure.unavailable
        }
        onAvailabilityChanged?(true)
    }

    func stop() {}
    func setPreviewPointerTracking(_ enabled: Bool) {}
}
