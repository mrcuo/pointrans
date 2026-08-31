import AppKit
import SwiftUI
import Translation

struct OnboardingView: View {
    @Bindable var controller: TranslationController
    @Bindable var permissions: PermissionCoordinator
    @Bindable var languagePacks: LanguagePackManager
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var welcomeOptionConfirmed = false
    @State private var welcomeAdvanceTask: Task<Void, Never>?
    @State private var guidedFinishTask: Task<Void, Never>?

    private var stage: OnboardingStage { controller.preferences.onboardingStage }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 52)
                .padding(.vertical, 28)
            bottomBar
        }
        .frame(width: 640, height: 620)
        .background(PointTheme.background(colorScheme))
        .translationTask(languagePacks.configuration) { session in
            await languagePacks.performPreparation(using: session)
        }
        .background {
            LeftOptionConfirmationMonitor(
                isEnabled: stage == .welcome && !welcomeOptionConfirmed,
                onPress: confirmWelcomeOption
            )
            .frame(width: 0, height: 0)
        }
        .task { enter(stage) }
        .onChange(of: stage) { _, next in enter(next) }
        .onChange(of: guidedExperienceComplete) { _, complete in
            if complete { scheduleAutomaticFinish() }
        }
        .onDisappear {
            welcomeAdvanceTask?.cancel()
            welcomeAdvanceTask = nil
            guidedFinishTask?.cancel()
            guidedFinishTask = nil
        }
        .accessibilityIdentifier("onboarding-window")
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            PointBrandLogo(height: 25)
            Spacer()
            Text(String(format: String(localized: "Step %d of 5"), stageIndex))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .frame(height: 68)
        .overlay(alignment: .bottom) { Rectangle().fill(PointTheme.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .welcome:
            welcomeStage
        case .accessibility:
            permissionStage(
                icon: "accessibility",
                title: String(localized: "Allow Accessibility"),
                detail: String(localized: "Required to listen for Left Option and read the word under your pointer."),
                state: permissions.accessibility,
                action: permissions.requestAccessibility
            )
        case .screenCapture:
            permissionStage(
                icon: "record.circle",
                title: String(localized: "Allow Screen Recording"),
                detail: String(localized: "Required for text inside images, PDFs, and apps that do not expose readable text. Only a small area near the pointer is processed on this Mac; screenshots are never saved or uploaded."),
                state: permissions.screenCapture,
                action: permissions.requestScreenCapture
            )
        case .languagePack:
            languagePackStage
        case .guidedExperience:
            guidedExperience
        case .complete:
            EmptyView()
        }
    }

    private var welcomeStage: some View {
        VStack(spacing: 20) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(PointTheme.cobalt)
            Text(String(localized: "Point at a word. Understand it."))
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(String(localized: "Hold Left Option and keep the pointer over English or Chinese text. Pointrans detects the language and shows the translation beside your pointer."))
                .font(.system(size: 14.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 450)
            Text("⌥  Left Option")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(welcomeOptionConfirmed ? Color.white : PointTheme.cobalt)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    welcomeOptionConfirmed ? PointTheme.cobalt : PointTheme.cobalt.opacity(0.09),
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(PointTheme.cobalt.opacity(welcomeOptionConfirmed ? 0 : 0.16))
                }
                .scaleEffect(welcomeOptionConfirmed ? 1.06 : 1)
                .shadow(
                    color: PointTheme.cobalt.opacity(welcomeOptionConfirmed ? 0.28 : 0),
                    radius: 10,
                    y: 3
                )
                .animation(.easeOut(duration: 0.12), value: welcomeOptionConfirmed)
                .accessibilityIdentifier("welcome-left-option-badge")
                .accessibilityValue(
                    welcomeOptionConfirmed
                        ? String(localized: "Left Option recognized")
                        : String(localized: "Waiting for Left Option")
                )
            Text(String(localized: "Press Left Option once to continue"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(welcomeOptionConfirmed ? PointTheme.cobalt : Color.secondary)
        }
    }

    private func permissionStage(
        icon: String,
        title: String,
        detail: String,
        state: PermissionState,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(PointTheme.cobalt)
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text(String(localized: "Required"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.orange.opacity(0.1), in: Capsule())
            if state == .granted {
                Label(String(localized: "Permission granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14, weight: .semibold))
            } else if state == .restartRequired {
                VStack(spacing: 10) {
                    Text(String(localized: "Restart Pointrans to finish this permission. Your setup progress is saved."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "Quit and reopen Pointrans")) { NSApp.terminate(nil) }
                        .buttonStyle(.borderedProminent)
                        .tint(PointTheme.cobalt)
                }
            } else if state == .requesting || state == .checking {
                ProgressView(String(localized: "Waiting for System Settings…"))
                    .controlSize(.small)
            } else {
                Button(String(localized: "Open System Settings"), action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(PointTheme.cobalt)
                    .controlSize(.large)
            }
        }
    }

    private var languagePackStage: some View {
        VStack(spacing: 18) {
            Image(systemName: "translate")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(PointTheme.cobalt)
            Text(String(localized: "Preparing English and Chinese"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(String(localized: "Pointrans is preparing Apple's on-device translation languages. This built-in capability must be ready before the guided experience."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            switch languagePacks.status {
            case .installed:
                Label(String(localized: "Language capability is ready"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14, weight: .semibold))
            case .checking, .preparing:
                ProgressView(String(localized: "Preparing language capability…"))
                    .controlSize(.small)
            case .failed:
                VStack(spacing: 9) {
                    Text(String(localized: "Language preparation could not finish. Check your connection and try again."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Retry")) { languagePacks.retry() }
                }
            case .unsupported:
                Text(String(localized: "The required Apple Translation language pair is unavailable on this Mac."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var guidedExperience: some View {
        VStack(spacing: 13) {
            Text(String(localized: "Try it once. You're ready."))
                .font(.system(size: 25, weight: .bold, design: .rounded))
            Text(guidedInstruction)
                .font(.system(size: 13.5))
                .foregroundStyle(guidedExperienceComplete ? .green : .secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)

            GuidedSampleTextView { frame in
                controller.updateTutorialTarget(
                    appKitFrame: frame,
                    word: OnboardingProgressPolicy.guidedTargetWord,
                    context: GuidedSampleTextView.sentence,
                    targetUTF16Range: GuidedSampleTextView.targetRange
                )
            }
                .frame(height: 68)
                .padding(.horizontal, 18)
                .background(PointTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(
                            controller.isTriggerModifierDown ? PointTheme.cobalt : PointTheme.cobalt.opacity(0.25),
                            lineWidth: controller.isTriggerModifierDown ? 2 : 1
                        )
                }
                .shadow(
                    color: PointTheme.cobalt.opacity(controller.isTriggerModifierDown ? 0.16 : 0),
                    radius: 9
                )
                .animation(.easeOut(duration: 0.12), value: controller.isTriggerModifierDown)
                .accessibilityIdentifier("guided-sample")

            guidedResultCard
        }
    }

    private var guidedInstruction: String {
        if guidedExperienceComplete {
            return String(localized: "That's it — Pointrans is ready in your menu bar.")
        }
        if case .loading = controller.insightPhase {
            return String(localized: "Pointrans is reading the sentence. No other action is needed.")
        }
        if guidedTranslationComplete {
            return String(localized: "Translation is ready. Now ask what it means in this sentence.")
        }
        if controller.isTriggerModifierDown {
            return String(localized: "Great — keep holding for a moment.")
        }
        return String(localized: "Move the pointer onto the blue word, then hold Left Option.")
    }

    private var guidedResultCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                guidedStepBadge(number: 1, done: guidedTranslationComplete)
                Text(String(localized: "Translate the blue word"))
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Text("⌥  Left Option")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(controller.isTriggerModifierDown ? Color.white : PointTheme.cobalt)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        controller.isTriggerModifierDown ? PointTheme.cobalt : PointTheme.cobalt.opacity(0.08),
                        in: Capsule()
                    )
            }

            Divider()

            if let base = controller.baseTranslation,
               let request = controller.currentRequest {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(request.word)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(base.primaryText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PointTheme.cobalt)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                guidedContextSection
            } else if case .extracting = controller.basePhase {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Reading the word under your pointer…"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if case .failed(_, let failure) = controller.basePhase {
                guidedRetryRow(message: guidedFailureText(failure))
            } else {
                Label(
                    String(localized: "The blue word is the target. Pointrans responds while Left Option is held."),
                    systemImage: "cursorarrow"
                )
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PointTheme.controlFill(colorScheme), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityIdentifier("guided-live-result")
    }

    @ViewBuilder
    private var guidedContextSection: some View {
        Divider()
        switch controller.insightPhase {
        case .idle:
            Button {
                controller.requestContextInsight()
            } label: {
                HStack(spacing: 9) {
                    guidedStepBadge(number: 2, done: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "See what it means in this sentence"))
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(String(localized: "Pointrans will explain this exact use."))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                }
                .foregroundStyle(PointTheme.cobalt)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guided-context-button")

        case .loading:
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Understanding this sentence…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

        case .ready(_, let result):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    guidedStepBadge(number: 2, done: true)
                    Text(result.insight.contextualMeaning)
                        .font(.system(size: 14.5, weight: .semibold))
                    Spacer()
                    Text(result.route == .onDevice ? String(localized: "On this Mac") : String(localized: "Online"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(result.insight.explanation)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

        case .failed(_, let failure):
            switch failure {
            case .onlineUnavailable:
                onlineExplanationFailure(serviceNeedsUpdate: false)
            case .onlineServiceIncompatible:
                onlineExplanationFailure(serviceNeedsUpdate: true)
            default:
                if OnlineExplanationConsentPolicy.shouldPrompt(
                    failure: failure,
                    consent: controller.preferences.cloudContextConsent
                ) {
                    onlineExplanationConsent
                } else if failure == .aiUnavailable,
                          controller.preferences.cloudContextConsent == .denied {
                    onlineExplanationRecovery
                } else {
                    guidedRetryRow(message: guidedFailureText(failure), retriesContext: true)
                }
            }
        }
    }

    private var onlineExplanationConsent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(String(localized: "This Mac couldn't create the extra explanation."))
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "To continue, Pointrans can send only “breakthrough” and this sample sentence for an online explanation. It never sends a screenshot or the app you're using."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(String(localized: "Not now")) {
                    controller.setCloudContextConsent(.denied)
                }
                Spacer()
                Button(String(localized: "Use online explanation")) {
                    controller.setCloudContextConsent(.allowed)
                    controller.requestContextInsight()
                }
                .buttonStyle(.borderedProminent)
                .tint(PointTheme.cobalt)
            }
        }
    }

    private var onlineExplanationRecovery: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(String(localized: "An explanation isn't available on this Mac right now."))
                .font(.system(size: 12.5, weight: .semibold))
            HStack {
                Button(String(localized: "Try again on this Mac")) {
                    controller.requestContextInsight(allowsOnlineFallback: false)
                }
                Spacer()
                Button(String(localized: "Use online explanation")) {
                    controller.setCloudContextConsent(.allowed)
                    controller.requestContextInsight()
                }
                .buttonStyle(.borderedProminent)
                .tint(PointTheme.cobalt)
            }
        }
    }

    private func onlineExplanationFailure(serviceNeedsUpdate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(serviceNeedsUpdate
                 ? String(localized: "Online explanation needs a service update.")
                 : String(localized: "Online explanation couldn't finish."))
                .font(.system(size: 12.5, weight: .semibold))
            Text(serviceNeedsUpdate
                 ? String(localized: "The word translation is complete, but the online explanation service is not ready for this version yet.")
                 : String(localized: "The word translation is complete. Try this Mac again or check the online explanation."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(String(localized: "Try again on this Mac")) {
                    controller.requestContextInsight(allowsOnlineFallback: false)
                }
                Spacer()
                Button(String(localized: "Check online again")) {
                    controller.requestContextInsight()
                }
                .buttonStyle(.borderedProminent)
                .tint(PointTheme.cobalt)
            }
        }
    }

    private func guidedRetryRow(message: String, retriesContext: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
            Button(String(localized: "Try again")) {
                if retriesContext {
                    controller.requestContextInsight()
                } else {
                    controller.retryTutorialAttempt()
                }
            }
        }
    }

    private func guidedStepBadge(number: Int, done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? Color.green : PointTheme.cobalt.opacity(0.11))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PointTheme.cobalt)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var bottomBar: some View {
        HStack {
            if stage != .welcome {
                Button(String(localized: "Back")) { moveBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button(String(localized: "Quit Pointrans")) { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            if stage == .guidedExperience {
                Text(String(localized: "Setup finishes automatically after the two actions."))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if stage == .welcome {
                EmptyView()
            } else {
                Button(continueTitle) { moveForward() }
                    .buttonStyle(.borderedProminent)
                    .tint(PointTheme.cobalt)
                    .disabled(!canContinue)
                    .accessibilityIdentifier("onboarding-continue-button")
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 70)
        .overlay(alignment: .top) { Rectangle().fill(PointTheme.hairline).frame(height: 1) }
    }

    private var canContinue: Bool {
        OnboardingProgressPolicy.canAdvance(
            from: stage,
            accessibilityGranted: permissions.accessibilityGranted,
            screenCaptureGranted: permissions.screenCaptureGranted,
            languagePackReady: languagePacks.isReady,
            welcomeTriggerConfirmed: welcomeOptionConfirmed
        )
    }

    private var guidedExperienceComplete: Bool {
        OnboardingProgressPolicy.canCompleteOnboarding(
            accessibilityGranted: permissions.accessibilityGranted,
            screenCaptureGranted: permissions.screenCaptureGranted,
            languagePackReady: languagePacks.isReady,
            word: controller.currentRequest?.word,
            translation: controller.baseTranslation,
            insight: controller.insight
        )
    }

    private var guidedTranslationComplete: Bool {
        controller.currentRequest?.word.localizedCaseInsensitiveCompare(OnboardingProgressPolicy.guidedTargetWord) == .orderedSame &&
            controller.baseTranslation?.primaryText.isEmpty == false
    }

    private var continueTitle: String { String(localized: "Continue") }

    private var stageIndex: Int {
        switch stage {
        case .welcome: 1
        case .accessibility: 2
        case .screenCapture: 3
        case .languagePack: 4
        case .guidedExperience, .complete: 5
        }
    }

    private func moveForward() {
        let next: OnboardingStage = switch stage {
        case .welcome: .accessibility
        case .accessibility: .screenCapture
        case .screenCapture: .languagePack
        case .languagePack: .guidedExperience
        case .guidedExperience, .complete: stage
        }
        move(to: next)
    }

    private func moveBack() {
        let prior: OnboardingStage = switch stage {
        case .welcome, .accessibility: .welcome
        case .screenCapture: .accessibility
        case .languagePack: .screenCapture
        case .guidedExperience: .languagePack
        case .complete: .guidedExperience
        }
        move(to: prior)
    }

    private func move(to next: OnboardingStage) {
        if stage == .guidedExperience {
            controller.setTutorialMode(false)
            controller.stop()
        }
        controller.preferences.onboardingStage = next
    }

    private func enter(_ next: OnboardingStage) {
        guidedFinishTask?.cancel()
        guidedFinishTask = nil
        if next == .welcome {
            welcomeAdvanceTask?.cancel()
            welcomeAdvanceTask = nil
            welcomeOptionConfirmed = false
        } else {
            welcomeAdvanceTask?.cancel()
            welcomeAdvanceTask = nil
        }
        permissions.refresh()
        if next == .languagePack { languagePacks.ensureRequiredPreparation() }
        if next == .guidedExperience {
            controller.closePanel()
            controller.setTutorialMode(true)
            controller.setTranslationEnabled(true)
            controller.start()
        }
    }

    private func scheduleAutomaticFinish() {
        guard stage == .guidedExperience, guidedFinishTask == nil else { return }
        guidedFinishTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(850))
            } catch {
                return
            }
            guard stage == .guidedExperience, guidedExperienceComplete else { return }
            finish()
        }
    }

    private func confirmWelcomeOption() {
        guard stage == .welcome, !welcomeOptionConfirmed else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            welcomeOptionConfirmed = true
        }
        welcomeAdvanceTask?.cancel()
        welcomeAdvanceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(360))
            } catch {
                return
            }
            guard stage == .welcome, welcomeOptionConfirmed else { return }
            move(to: .accessibility)
        }
    }

    private func finish() {
        guard guidedExperienceComplete else { return }
        controller.setTutorialMode(false)
        controller.preferences.onboardingVersion = AppPreferences.currentOnboardingVersion
        controller.preferences.onboardingStage = .complete
        controller.start()
        onComplete()
    }

    private func guidedFailureText(_ failure: TranslationFailure) -> String {
        switch failure {
        case .quotaExhausted: String(localized: "Cloud context quota is exhausted. Try again after it resets.")
        case .aiUnavailable:
            controller.preferences.cloudContextConsent == .allowed
                ? String(localized: "The explanation is temporarily unavailable.")
                : String(localized: "The explanation is not available on this Mac right now.")
        case .onlineUnavailable: String(localized: "Online explanation couldn't finish.")
        case .onlineServiceIncompatible: String(localized: "Online explanation needs a service update.")
        case .permissionRequired: String(localized: "Both required permissions must remain enabled.")
        case .translationUnavailable: String(localized: "All built-in translation routes failed. Check the language capability and try again.")
        case .message(let value): value
        default: String(localized: "The guided action did not finish. Keep the pointer on the sample and try again.")
        }
    }
}

private struct LeftOptionConfirmationMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onPress: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.update(isEnabled: isEnabled, onPress: onPress)
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.update(isEnabled: isEnabled, onPress: onPress)
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.stop()
    }

    @MainActor
    final class MonitorView: NSView {
        private var localMonitor: Any?
        private var onPress: (() -> Void)?

        func update(isEnabled: Bool, onPress: @escaping () -> Void) {
            self.onPress = onPress
            isEnabled ? start() : stop()
        }

        func start() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard FixedTriggerPolicy.acceptsOnboardingConfirmation(
                    keyCode: CGKeyCode(event.keyCode),
                    isPressed: event.modifierFlags.contains(.option)
                ) else { return event }
                self?.onPress?()
                return event
            }
        }

        func stop() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
            }
            localMonitor = nil
        }

    }
}
