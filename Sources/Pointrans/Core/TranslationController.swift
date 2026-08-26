import AppKit
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class TranslationController {
    private(set) var state: TranslationState = .idle
    private(set) var panelMode: PanelMode = .hidden {
        didSet {
            monitor.setPreviewPointerTracking(panelMode.isPreview)
            onPanelUpdate?()
        }
    }
    private(set) var currentRequest: TranslationRequest?
    private(set) var extraction: ExtractionResult?
    private(set) var baseTranslation: BaseTranslation?
    private(set) var insight: InsightResult?
    private(set) var panelFrameQuartz: CGRect?
    private(set) var isPointerInsidePanel = false
    private(set) var monitorAvailable = false

    let preferences: AppPreferences

    @ObservationIgnored var onPanelUpdate: (() -> Void)?

    private let environment: ProviderEnvironment
    private let monitor: EventTapMonitor
    private var hoverMachine: HoverIntentMachine
    private var dwellTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var previewDismissTask: Task<Void, Never>?
    private var safeCorridor: SafeCorridor?
    private var corridorExpiresAt: TimeInterval = 0
    private var isTriggerModifierDown = false

    init(
        preferences: AppPreferences,
        environment: ProviderEnvironment,
        monitor: EventTapMonitor? = nil
    ) {
        self.preferences = preferences
        self.environment = environment
        self.monitor = monitor ?? EventTapMonitor(modifier: preferences.triggerModifier)
        hoverMachine = HoverIntentMachine(configuration: .init(dwellDuration: preferences.hoverDelay))
        self.monitor.onEvent = { [weak self] event in self?.handle(event) }
        self.monitor.onAvailabilityChanged = { [weak self] value in self?.monitorAvailable = value }
    }

    var accessibilityGranted: Bool { environment.permissions.accessibilityGranted }
    var screenCaptureGranted: Bool { environment.permissions.screenCaptureGranted }

    func start() {
        guard preferences.translationEnabled else { return }
        do {
            try monitor.start()
        } catch {
            monitorAvailable = false
        }
    }

    func stop() {
        monitor.stop()
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

    func setTriggerModifier(_ modifier: TriggerModifier) {
        preferences.triggerModifier = modifier
        monitor.updateModifier(modifier)
    }

    func setHoverDelay(_ delay: Double) {
        preferences.hoverDelay = delay
        hoverMachine.configuration.dwellDuration = preferences.hoverDelay
    }

    func setDirection(_ direction: TranslationDirection) {
        guard preferences.direction != direction else { return }
        preferences.direction = direction
        cancelAllTasks()
        closePanel()
    }

    func setAIEnabled(_ enabled: Bool) {
        guard preferences.aiEnabled != enabled else { return }
        preferences.aiEnabled = enabled
        guard !enabled else { return }

        // The AI switch is also a privacy stop control. Turning it off must
        // cancel any in-flight device/cloud work and remove previously
        // generated context without disturbing the base dictionary result.
        aiTask?.cancel()
        aiTask = nil
        insight = nil
        if let request = currentRequest,
           let base = baseTranslation,
           panelMode != .hidden {
            state = .ready(requestID: request.id, base, nil)
        }
    }

    func requestAccessibilityPermission() {
        environment.permissions.requestAccessibility()
    }

    func requestScreenCapturePermission() {
        Task { _ = await environment.permissions.requestScreenCapture() }
    }

    func updatePanelFrame(appKitFrame: CGRect) {
        let quartzFrame = ScreenCoordinates.appKitRectToQuartz(appKitFrame)
        panelFrameQuartz = quartzFrame
        if let anchor = currentRequest?.screenPoint {
            safeCorridor = SafeCorridor(anchor: anchor, target: quartzFrame, padding: 10)
            corridorExpiresAt = ProcessInfo.processInfo.systemUptime + 0.7
        }
    }

    func requestContextInsight() {
        guard preferences.aiEnabled,
              let request = currentRequest,
              let base = baseTranslation,
              panelMode != .hidden else { return }
        if case .preview = panelMode { pinPanel() }

        aiTask?.cancel()
        state = .enriching(requestID: request.id, base)
        aiTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await environment.analyzer.analyze(request: request, base: base)
                try Task.checkCancellation()
                guard self.currentRequest?.id == request.id else { return }
                self.insight = result
                self.state = .ready(requestID: request.id, self.baseTranslation ?? base, result)
            } catch is CancellationError {
                return
            } catch let error as ContextAnalyzerError {
                guard !Task.isCancelled,
                      self.preferences.aiEnabled,
                      self.currentRequest?.id == request.id else { return }
                self.state = .failed(requestID: request.id, self.translationFailure(for: error))
            } catch {
                guard !Task.isCancelled,
                      self.preferences.aiEnabled,
                      self.currentRequest?.id == request.id else { return }
                self.state = .failed(requestID: request.id, .aiUnavailable)
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
        enrichmentTask?.cancel()
        aiTask?.cancel()
        previewDismissTask?.cancel()
        panelMode = .hidden
        panelFrameQuartz = nil
        safeCorridor = nil
        isPointerInsidePanel = false
        currentRequest = nil
        extraction = nil
        baseTranslation = nil
        insight = nil
        state = .idle
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
            source: .dictionaryAndApple
        )
        currentRequest = request
        extraction = extracted
        baseTranslation = base
        state = .ready(requestID: id, base, nil)
        panelMode = pinned ? .pinned(sessionID: id) : .preview(sessionID: id)
    }
    #endif

    private func handle(_ event: TriggerEvent) {
        guard preferences.translationEnabled else { return }
        switch event {
        case .modifierPressed(let point, let timestamp):
            guard !panelMode.isPinned else { return }
            isTriggerModifierDown = true
            if case .preview = panelMode {
                dismissPreview()
            }
            apply(hoverMachine.modifierPressed(at: point, timestamp: timestamp))

        case .modifierReleased(let point, let timestamp):
            isTriggerModifierDown = false
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
                enrichmentTask?.cancel()
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
            state = .failed(requestID: nil, .extractionUnavailable)
            apply(hoverMachine.extractionFailed(generation: generation))
            return
        }

        let requestID = UUID()
        let direction = preferences.direction
        clearUnpresentedSession()
        state = .extracting(requestID: requestID)
        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                let extracted = try await environment.extractor.extract(
                    at: anchor,
                    displayID: displayID,
                    direction: direction
                )
                try Task.checkCancellation()
                guard case .extracting(_, let currentGeneration) = hoverMachine.state,
                      currentGeneration == generation else { return }

                let request = TranslationRequest(
                    id: requestID,
                    screenPoint: anchor,
                    displayID: displayID,
                    word: extracted.word,
                    context: TextTokenizer.truncatedUTF16(extracted.context, maximumLength: 600),
                    direction: direction,
                    createdAt: Date()
                )
                currentRequest = request
                extraction = extracted

                let base: BaseTranslation
                do {
                    base = try await environment.translator.translate(
                        word: request.word,
                        context: request.context,
                        direction: request.direction
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard case .extracting(_, let currentGeneration) = hoverMachine.state,
                          currentGeneration == generation else { return }
                    state = .failed(requestID: requestID, .translationUnavailable)
                    hoverMachine.reset()
                    return
                }
                try Task.checkCancellation()
                guard currentRequest?.id == requestID,
                      case .extracting(_, let currentGeneration) = hoverMachine.state,
                      currentGeneration == generation else { return }
                baseTranslation = base
                hoverMachine.extractionSucceeded(sessionID: requestID, generation: generation)
                state = .baseReady(requestID: requestID, base)
                panelMode = .preview(sessionID: requestID)
                beginDeviceEnrichment(for: request, base: base)
            } catch is CancellationError {
                return
            } catch {
                guard case .extracting(_, let currentGeneration) = hoverMachine.state,
                      currentGeneration == generation else { return }
                state = .failed(requestID: requestID, .noTextFound)
                apply(hoverMachine.extractionFailed(generation: generation))
            }
        }
    }

    private func beginDeviceEnrichment(for request: TranslationRequest, base: BaseTranslation) {
        enrichmentTask?.cancel()
        enrichmentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let enriched = try await environment.translator.enrich(
                    base,
                    word: request.word,
                    context: request.context,
                    direction: request.direction
                )
                try Task.checkCancellation()
                guard currentRequest?.id == request.id else { return }
                baseTranslation = enriched
                state = .ready(requestID: request.id, enriched, insight)
            } catch is CancellationError {
                return
            } catch {
                guard currentRequest?.id == request.id else { return }
                if base.meanings.isEmpty {
                    state = .failed(requestID: request.id, .translationUnavailable)
                } else {
                    state = .ready(requestID: request.id, base, insight)
                }
            }
        }
    }

    private func dismissPreview() {
        guard case .preview(let sessionID) = panelMode else { return }
        previewDismissTask?.cancel()
        panelMode = .hidden
        // The panel coordinator uses this ID to guard its animation completion.
        if currentRequest?.id == sessionID {
            cancelSessionWork()
            state = .idle
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
        enrichmentTask?.cancel()
        aiTask?.cancel()
        workTask = nil
        enrichmentTask = nil
        aiTask = nil
    }

    private func clearUnpresentedSession() {
        guard panelMode == .hidden else { return }
        currentRequest = nil
        extraction = nil
        baseTranslation = nil
        insight = nil
        panelFrameQuartz = nil
        safeCorridor = nil
        isPointerInsidePanel = false
    }

    private func clearSessionData(sessionID: UUID) {
        guard currentRequest?.id == sessionID else { return }
        currentRequest = nil
        extraction = nil
        baseTranslation = nil
        insight = nil
        panelFrameQuartz = nil
        safeCorridor = nil
        isPointerInsidePanel = false
        if state.requestID == sessionID || state == .idle {
            state = .idle
        }
    }

    private func cancelAllTasks() {
        dwellTask?.cancel()
        previewDismissTask?.cancel()
        cancelSessionWork()
    }

    private func translationFailure(for error: ContextAnalyzerError) -> TranslationFailure {
        switch error {
        case .invalidInput: .message(String(localized: "The selected text cannot be analyzed."))
        case .cancelled: .cancelled
        case .safetyRefusal: .message(String(localized: "This context cannot be analyzed on device."))
        case .unavailable, .transient: .aiUnavailable
        case .quotaExhausted(let resetAt): .quotaExhausted(resetAt: resetAt)
        case .unauthorized: .aiUnavailable
        }
    }

    private func displayID(containing point: CGPoint) -> CGDirectDisplayID? {
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        let result = CGGetDisplaysWithPoint(point, 1, &display, &count)
        return result == .success && count == 1 ? display : nil
    }
}
