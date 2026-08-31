import AppKit
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class TranslationController {
    private(set) var basePhase: BaseTranslationPhase = .idle
    private(set) var insightPhase: ContextInsightPhase = .idle
    private(set) var panelMode: PanelMode = .hidden {
        didSet {
            monitor.setPreviewPointerTracking(panelMode.isPreview)
            onPanelUpdate?()
        }
    }
    private(set) var currentRequest: TranslationRequest?
    private(set) var extraction: ExtractionResult?
    private(set) var panelFrameQuartz: CGRect?
    private(set) var isPointerInsidePanel = false
    private(set) var accessibilityGranted: Bool { didSet { onStatusUpdate?() } }
    private(set) var screenCaptureGranted: Bool { didSet { onStatusUpdate?() } }
    private(set) var triggerRuntimeState: TriggerRuntimeState = .stopped {
        didSet { onStatusUpdate?() }
    }

    let preferences: AppPreferences

    @ObservationIgnored var onPanelUpdate: (() -> Void)?
    @ObservationIgnored var onStatusUpdate: (() -> Void)?

    private let environment: ProviderEnvironment
    private let monitor: any EventMonitoring
    private var hoverMachine: HoverIntentMachine
    private var dwellTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var loadingPreviewTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var previewDismissTask: Task<Void, Never>?
    private var monitorRecoveryTask: Task<Void, Never>?
    private var safeCorridor: SafeCorridor?
    private var corridorExpiresAt: TimeInterval = 0
    private(set) var isTriggerModifierDown = false
    private(set) var isTutorialMode = false
    private var tutorialTarget: TutorialTarget?

    private struct TutorialTarget {
        let regionQuartz: CGRect
        let word: String
        let context: String
        let targetUTF16Range: NSRange
    }

    init(
        preferences: AppPreferences,
        environment: ProviderEnvironment,
        monitor: (any EventMonitoring)? = nil
    ) {
        self.preferences = preferences
        self.environment = environment
        self.monitor = monitor ?? EventTapMonitor()
        accessibilityGranted = environment.permissions.accessibilityGranted
        screenCaptureGranted = environment.permissions.screenCaptureGranted
        hoverMachine = HoverIntentMachine(configuration: .init(dwellDuration: preferences.hoverDelay))
        self.monitor.onEvent = { [weak self] event in self?.handle(event) }
        self.monitor.onAvailabilityChanged = { [weak self] value in self?.handleMonitorAvailability(value) }
    }

    var monitorAvailable: Bool { triggerRuntimeState == .active }
    var baseTranslation: BaseTranslation? { basePhase.translation }
    var insight: InsightResult? { insightPhase.result }

    var state: TranslationState {
        if case .failed(let requestID, let failure) = basePhase {
            return .failed(requestID: requestID, failure)
        }
        guard let requestID = basePhase.requestID else { return .idle }
        if case .extracting = basePhase { return .extracting(requestID: requestID) }
        guard let base = baseTranslation else { return .idle }
        switch insightPhase {
        case .loading:
            return .enriching(requestID: requestID, base)
        case .ready(_, let result):
            return .ready(requestID: requestID, base, result)
        case .failed(_, let failure):
            return .failed(requestID: requestID, failure)
        case .idle:
            switch basePhase {
            case .ready:
                return .ready(requestID: requestID, base, nil)
            case .idle, .extracting, .failed:
                return .idle
            }
        }
    }

    func start() {
        refreshCapabilities()
    }

    func stop() {
        monitorRecoveryTask?.cancel()
        monitorRecoveryTask = nil
        monitor.stop()
        triggerRuntimeState = .stopped
        isTriggerModifierDown = false
        hoverMachine.reset()
        cancelAllTasks()
    }

    func setTranslationEnabled(_ enabled: Bool) {
        preferences.translationEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
            closePanel()
        }
    }

    func setHoverDelay(_ delay: Double) {
        preferences.hoverDelay = delay
        hoverMachine.configuration.dwellDuration = preferences.hoverDelay
    }

    func setCloudContextConsent(_ consent: CloudContextConsent) {
        preferences.cloudContextConsent = consent
        guard consent != .allowed, case .loading = insightPhase else { return }
        aiTask?.cancel()
        aiTask = nil
        insightPhase = .idle
    }

    func setTutorialMode(_ enabled: Bool) {
        isTutorialMode = enabled
        if !enabled {
            tutorialTarget = nil
            closePanel()
        }
        onPanelUpdate?()
    }

    /// Leaves the guarded sample area after a successful first-run session,
    /// while preserving the real pinned card the user just created. From this
    /// point onward the session behaves exactly like any normal translation.
    func completeTutorialModeKeepingResult() {
        guard isTutorialMode else { return }
        isTutorialMode = false
        tutorialTarget = nil
        onPanelUpdate?()
    }

    func updateTutorialTarget(
        appKitFrame: CGRect,
        word: String,
        context: String,
        targetUTF16Range: NSRange
    ) {
        tutorialTarget = TutorialTarget(
            regionQuartz: ScreenCoordinates.appKitRectToQuartz(appKitFrame),
            word: word,
            context: context,
            targetUTF16Range: targetUTF16Range
        )
    }

    func retryTutorialAttempt() {
        guard isTutorialMode else { return }
        closePanel()
    }

    func refreshCapabilities() {
        accessibilityGranted = environment.permissions.accessibilityGranted
        screenCaptureGranted = environment.permissions.screenCaptureGranted
        guard preferences.translationEnabled else {
            monitorRecoveryTask?.cancel()
            monitorRecoveryTask = nil
            monitor.stop()
            triggerRuntimeState = .stopped
            return
        }
        guard accessibilityGranted else {
            monitorRecoveryTask?.cancel()
            monitorRecoveryTask = nil
            monitor.stop()
            triggerRuntimeState = .waitingForAccessibility
            return
        }
        guard screenCaptureGranted else {
            monitorRecoveryTask?.cancel()
            monitorRecoveryTask = nil
            monitor.stop()
            triggerRuntimeState = .waitingForScreenCapture
            onStatusUpdate?()
            return
        }
        guard triggerRuntimeState != .active, triggerRuntimeState != .starting else { return }
        startMonitorWithRecovery()
    }

    func applicationDidBecomeActive() {
        refreshCapabilities()
    }

    func updatePanelFrame(appKitFrame: CGRect) {
        let quartzFrame = ScreenCoordinates.appKitRectToQuartz(appKitFrame)
        panelFrameQuartz = quartzFrame
        if let anchor = currentRequest?.screenPoint {
            safeCorridor = SafeCorridor(anchor: anchor, target: quartzFrame, padding: 10)
            corridorExpiresAt = ProcessInfo.processInfo.systemUptime + 0.7
        }
    }

    func requestContextInsight(allowsOnlineFallback: Bool? = nil) {
        guard let request = currentRequest,
              let base = baseTranslation,
              panelMode != .hidden else { return }
        if case .preview = panelMode { pinPanel() }

        aiTask?.cancel()
        insightPhase = .loading(requestID: request.id)
        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await environment.analyzer.analyze(
                    request: request,
                    base: base,
                    allowsCloudFallback: allowsOnlineFallback
                        ?? (self.preferences.cloudContextConsent == .allowed)
                )
                try Task.checkCancellation()
                guard self.currentRequest?.id == request.id else { return }
                self.insightPhase = .ready(requestID: request.id, result)
            } catch is CancellationError {
                return
            } catch let error as ContextAnalyzerError {
                guard !Task.isCancelled,
                      self.currentRequest?.id == request.id else { return }
                self.insightPhase = .failed(requestID: request.id, self.translationFailure(for: error))
            } catch {
                guard !Task.isCancelled,
                      self.currentRequest?.id == request.id else { return }
                self.insightPhase = .failed(requestID: request.id, .aiUnavailable)
            }
        }
    }

    func pinPanel() {
        hoverMachine.pinPreview()
        guard let id = currentRequest?.id else { return }
        panelMode = .pinned(sessionID: id)
        previewDismissTask?.cancel()
        previewDismissTask = nil
    }

    func closePanel() {
        hoverMachine.reset()
        dwellTask?.cancel()
        workTask?.cancel()
        loadingPreviewTask?.cancel()
        aiTask?.cancel()
        previewDismissTask?.cancel()
        panelMode = .hidden
        panelFrameQuartz = nil
        safeCorridor = nil
        isPointerInsidePanel = false
        currentRequest = nil
        extraction = nil
        basePhase = .idle
        insightPhase = .idle
    }

    func panelHideAnimationCompleted(sessionID: UUID) {
        guard panelMode == .hidden, currentRequest?.id == sessionID else { return }
        clearSessionData(sessionID: sessionID)
    }

    /// Internal seam used by deterministic unit tests; production events arrive from EventTapMonitor.
    func receive(_ event: TriggerEvent) {
        handle(event)
    }

    #if DEBUG
    func loadUITestFixture(pinned: Bool = false) {
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        let id = UUID()
        let request = TranslationRequest(
            id: id,
            screenPoint: point,
            displayID: displayID,
            word: "pulling",
            context: "She kept pulling the thread until the knot came loose.",
            targetUTF16Range: NSRange(location: 9, length: 7),
            direction: .englishToChinese,
            createdAt: Date()
        )
        let extracted = ExtractionResult(
            word: request.word,
            context: request.context,
            bounds: CGRect(x: point.x - 20, y: point.y - 8, width: 48, height: 18),
            confidence: 1,
            source: .accessibility
        )
        let base = BaseTranslation(
            meanings: ["拉动", "牵引", "抽出"],
            deviceTranslation: "拉动",
            phonetic: "/ˈpʊlɪŋ/",
            pinyin: nil,
            source: .deviceAI
        )
        currentRequest = request
        extraction = extracted
        basePhase = .ready(requestID: id, base)
        insightPhase = .idle
        panelMode = pinned ? .pinned(sessionID: id) : .preview(sessionID: id)
    }
    #endif

    private func handle(_ event: TriggerEvent) {
        guard preferences.translationEnabled else { return }
        switch event {
        case .modifierPressed(let point, let timestamp):
            if isTutorialMode, tutorialTarget?.regionQuartz.contains(point) != true { return }
            guard !panelMode.isPinned else { return }
            isTriggerModifierDown = true
            if case .preview = panelMode {
                dismissPreview()
            }
            apply(hoverMachine.modifierPressed(at: point, timestamp: timestamp))

        case .modifierReleased(let point, let timestamp):
            isTriggerModifierDown = false
            if case .extracting = basePhase {
                if panelMode.isPreview { panelMode = .hidden }
                apply(hoverMachine.modifierReleased())
                clearUnpresentedSession()
                return
            }
            if shouldPreservePreview(at: point, timestamp: timestamp) {
                if panelFrameQuartz?.contains(point) == true {
                    previewDismissTask?.cancel()
                    previewDismissTask = nil
                } else {
                    let remainingCorridorTime = max(0, corridorExpiresAt - timestamp)
                    schedulePreviewDismiss(after: remainingCorridorTime + 0.18)
                }
                return
            }
            apply(hoverMachine.modifierReleased())

        case .pointerMoved(let point, let timestamp):
            if handlePanelMovement(point, timestamp: timestamp) { return }
            // Preview tracking remains active briefly after key release so the
            // pointer can cross the safe corridor. It must never re-arm a new
            // translation without another explicit modifier press.
            if panelMode.isPreview, !isTriggerModifierDown {
                dismissPreview()
                return
            }
            guard isTriggerModifierDown else { return }
            apply(hoverMachine.pointerMoved(to: point, timestamp: timestamp))

        case .primaryClick(let point, _):
            guard let frame = panelFrameQuartz else { return }
            if frame.contains(point), case .preview = panelMode {
                pinPanel()
            } else if !frame.contains(point), case .preview = panelMode {
                dismissPreview()
            }
        }
    }

    private func handlePanelMovement(_ point: CGPoint, timestamp: TimeInterval) -> Bool {
        guard case .preview = panelMode, let frame = panelFrameQuartz else { return panelMode.isPinned }
        if frame.contains(point) {
            isPointerInsidePanel = true
            previewDismissTask?.cancel()
            previewDismissTask = nil
            return true
        }
        if timestamp <= corridorExpiresAt, safeCorridor?.contains(point) == true {
            return true
        }
        if isPointerInsidePanel {
            isPointerInsidePanel = false
            schedulePreviewDismiss()
            return true
        }
        return false
    }

    private func shouldPreservePreview(at point: CGPoint, timestamp: TimeInterval) -> Bool {
        guard case .preview = panelMode else { return false }
        return panelFrameQuartz?.contains(point) == true ||
            (timestamp <= corridorExpiresAt && safeCorridor?.contains(point) == true)
    }

    private func apply(_ actions: [HoverIntentAction]) {
        for action in actions {
            switch action {
            case .scheduleDwell(let generation, let delay):
                dwellTask?.cancel()
                dwellTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self else { return }
                    self.apply(self.hoverMachine.dwellElapsed(generation: generation))
                }

            case .cancelDwell:
                dwellTask?.cancel()
                dwellTask = nil

            case .extract(let anchor, let generation):
                beginExtraction(anchor: anchor, generation: generation)

            case .cancelExtraction:
                workTask?.cancel()
                loadingPreviewTask?.cancel()
                if panelMode == .hidden {
                    clearUnpresentedSession()
                }

            case .dismissPreview:
                dismissPreview()
            }
        }
    }

    private func beginExtraction(anchor: CGPoint, generation: UInt64) {
        cancelSessionWork()
        guard let displayID = displayID(containing: anchor) else {
            basePhase = .failed(requestID: nil, .extractionUnavailable)
            apply(hoverMachine.extractionFailed(generation: generation))
            return
        }

        let requestID = UUID()
        clearUnpresentedSession()
        basePhase = .extracting(requestID: requestID)
        insightPhase = .idle
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let extracted: ExtractionResult
                if let guided = guidedExtraction(at: anchor) {
                    extracted = guided
                } else {
                    extracted = try await environment.extractor.extract(at: anchor, displayID: displayID)
                }
                try Task.checkCancellation()
                guard case .extracting(_, let currentGeneration) = hoverMachine.state,
                      currentGeneration == generation else { return }

                guard let direction = extracted.detectedLanguage.direction else {
                    throw ExtractionError.noTextAtPointer
                }
                let boundedContext = TextTokenizer.boundedContext(
                    extracted.context,
                    targetUTF16Range: extracted.targetUTF16Range
                ) ?? TextTokenizer.ContextWindow(
                    text: extracted.word,
                    targetUTF16Range: NSRange(location: 0, length: extracted.word.utf16.count)
                )
                let request = TranslationRequest(
                    id: requestID,
                    screenPoint: anchor,
                    displayID: displayID,
                    word: extracted.word,
                    context: boundedContext.text,
                    targetUTF16Range: boundedContext.targetUTF16Range,
                    direction: direction,
                    createdAt: Date()
                )
                currentRequest = request
                extraction = extracted
                scheduleLoadingPreview(for: requestID, generation: generation)

                let base: BaseTranslation
                do {
                    base = try await environment.translator.translate(request: request)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard case .extracting(_, let currentGeneration) = hoverMachine.state,
                          currentGeneration == generation else { return }
                    basePhase = .failed(requestID: requestID, .translationUnavailable)
                    hoverMachine.reset()
                    panelMode = .preview(sessionID: requestID)
                    schedulePreviewDismiss(after: 1.4)
                    return
                }
                try Task.checkCancellation()
                guard currentRequest?.id == requestID,
                      case .extracting(_, let currentGeneration) = hoverMachine.state,
                      currentGeneration == generation else { return }
                basePhase = .ready(requestID: requestID, base)
                hoverMachine.extractionSucceeded(sessionID: requestID, generation: generation)
                panelMode = .preview(sessionID: requestID)
            } catch is CancellationError {
                return
            } catch let error as ExtractionError {
                guard case .extracting(_, let currentGeneration) = hoverMachine.state,
                      currentGeneration == generation else { return }
                basePhase = .failed(requestID: requestID, extractionFailure(for: error))
                refreshCapabilities()
                if error == .accessibilityPermissionRequired || error == .screenCapturePermissionRequired {
                    hoverMachine.reset()
                } else {
                    apply(hoverMachine.extractionFailed(generation: generation))
                }
            } catch {
                guard case .extracting(_, let currentGeneration) = hoverMachine.state,
                      currentGeneration == generation else { return }
                basePhase = .failed(requestID: requestID, .noTextFound)
                apply(hoverMachine.extractionFailed(generation: generation))
            }
        }
    }

    private func guidedExtraction(at anchor: CGPoint) -> ExtractionResult? {
        guard isTutorialMode,
              let target = tutorialTarget,
              target.regionQuartz.contains(anchor) else { return nil }
        return ExtractionResult(
            word: target.word,
            context: target.context,
            targetUTF16Range: target.targetUTF16Range,
            bounds: target.regionQuartz,
            confidence: 1,
            source: .guidedSample,
            detectedLanguage: .detect(target.word)
        )
    }

    private func scheduleLoadingPreview(for requestID: UUID, generation: UInt64) {
        loadingPreviewTask?.cancel()
        loadingPreviewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self,
                  self.currentRequest?.id == requestID,
                  case .extracting(_, let currentGeneration) = self.hoverMachine.state,
                  currentGeneration == generation else { return }
            self.panelMode = .preview(sessionID: requestID)
        }
    }

    private func dismissPreview() {
        guard case .preview(let sessionID) = panelMode else { return }
        previewDismissTask?.cancel()
        panelMode = .hidden
        // The panel coordinator uses this ID to guard its animation completion.
        if currentRequest?.id == sessionID {
            cancelSessionWork()
        }
    }

    private func schedulePreviewDismiss() {
        schedulePreviewDismiss(after: 0.18)
    }

    private func schedulePreviewDismiss(after delay: TimeInterval) {
        previewDismissTask?.cancel()
        previewDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled else { return }
            self?.dismissPreview()
        }
    }

    private func cancelSessionWork() {
        workTask?.cancel()
        loadingPreviewTask?.cancel()
        aiTask?.cancel()
        workTask = nil
        loadingPreviewTask = nil
        aiTask = nil
    }

    private func clearUnpresentedSession() {
        guard panelMode == .hidden else { return }
        currentRequest = nil
        extraction = nil
        basePhase = .idle
        insightPhase = .idle
        panelFrameQuartz = nil
        safeCorridor = nil
        isPointerInsidePanel = false
    }

    private func clearSessionData(sessionID: UUID) {
        guard currentRequest?.id == sessionID else { return }
        currentRequest = nil
        extraction = nil
        basePhase = .idle
        insightPhase = .idle
        panelFrameQuartz = nil
        safeCorridor = nil
        isPointerInsidePanel = false
    }

    private func cancelAllTasks() {
        dwellTask?.cancel()
        previewDismissTask?.cancel()
        cancelSessionWork()
    }

    private func handleMonitorAvailability(_ available: Bool) {
        guard preferences.translationEnabled else {
            triggerRuntimeState = .stopped
            return
        }
        if available {
            monitorRecoveryTask?.cancel()
            monitorRecoveryTask = nil
            triggerRuntimeState = .active
        } else if accessibilityGranted && screenCaptureGranted {
            triggerRuntimeState = .recovering
            scheduleMonitorRecovery()
        } else if !accessibilityGranted {
            triggerRuntimeState = .waitingForAccessibility
        } else {
            triggerRuntimeState = .waitingForScreenCapture
        }
    }

    private func startMonitorWithRecovery() {
        triggerRuntimeState = .starting
        do {
            try monitor.start()
            if triggerRuntimeState == .starting { triggerRuntimeState = .active }
        } catch {
            triggerRuntimeState = .recovering
            scheduleMonitorRecovery()
        }
    }

    private func scheduleMonitorRecovery() {
        guard monitorRecoveryTask == nil else { return }
        monitorRecoveryTask = Task { [weak self] in
            let delays: [Duration] = [
                .milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)
            ]
            for delay in delays {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    self?.monitorRecoveryTask = nil
                    return
                }
                guard let self else { return }
                guard self.preferences.translationEnabled else {
                    self.monitorRecoveryTask = nil
                    return
                }
                self.accessibilityGranted = self.environment.permissions.accessibilityGranted
                self.screenCaptureGranted = self.environment.permissions.screenCaptureGranted
                guard self.accessibilityGranted else {
                    self.triggerRuntimeState = .waitingForAccessibility
                    self.monitorRecoveryTask = nil
                    return
                }
                guard self.screenCaptureGranted else {
                    self.triggerRuntimeState = .waitingForScreenCapture
                    self.monitorRecoveryTask = nil
                    return
                }
                self.triggerRuntimeState = .starting
                do {
                    try self.monitor.start()
                    if self.triggerRuntimeState == .starting { self.triggerRuntimeState = .active }
                    self.monitorRecoveryTask = nil
                    return
                } catch {
                    self.triggerRuntimeState = .recovering
                }
            }
            guard let self else { return }
            guard self.preferences.translationEnabled else {
                self.monitorRecoveryTask = nil
                return
            }
            self.triggerRuntimeState = .failed
            self.monitorRecoveryTask = nil
        }
    }

    private func extractionFailure(for error: ExtractionError) -> TranslationFailure {
        switch error {
        case .accessibilityPermissionRequired, .screenCapturePermissionRequired:
            .permissionRequired
        case .noTextAtPointer:
            .noTextFound
        case .unsupportedApplication, .captureFailed:
            .extractionUnavailable
        }
    }

    private func translationFailure(for error: ContextAnalyzerError) -> TranslationFailure {
        switch error {
        case .invalidInput: .message(String(localized: "The selected text cannot be analyzed."))
        case .cancelled: .cancelled
        case .safetyRefusal: .message(String(localized: "This context cannot be analyzed on device."))
        case .unavailable, .transient: .aiUnavailable
        case .onlineUnavailable, .unauthorized: .onlineUnavailable
        case .onlineServiceIncompatible: .onlineServiceIncompatible
        case .quotaExhausted(let resetAt): .quotaExhausted(resetAt: resetAt)
        }
    }

    private func displayID(containing point: CGPoint) -> CGDirectDisplayID? {
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        let result = CGGetDisplaysWithPoint(point, 1, &display, &count)
        return result == .success && count == 1 ? display : nil
    }
}
