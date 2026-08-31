import AppKit
import SwiftUI
import Translation

struct ControlCenterView: View {
    @Bindable var controller: TranslationController
    @Bindable var permissions: PermissionCoordinator
    @Bindable var languagePacks: LanguagePackManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)

            usageCard
                .padding(.horizontal, 20)
                .padding(.top, 16)

            delayControl
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Rectangle().fill(PointTheme.hairline).frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.vertical, 15)

            VStack(spacing: 8) {
                capabilityRow(
                    icon: "accessibility",
                    title: String(localized: "Accessibility"),
                    state: permissions.accessibility,
                    action: permissions.requestAccessibility
                )
                capabilityRow(
                    icon: "record.circle",
                    title: String(localized: "Screen Recording"),
                    state: permissions.screenCapture,
                    action: permissions.requestScreenCapture
                )
                languageRow
                privacyRow
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 12)
            footer
        }
        .frame(width: 360, height: 500)
        .background(PointTheme.background(colorScheme))
        .translationTask(languagePacks.configuration) { session in
            await languagePacks.performPreparation(using: session)
        }
        .task {
            permissions.refresh()
            if !languagePacks.isReady { languagePacks.ensureRequiredPreparation() }
        }
        .accessibilityIdentifier("control-center-main")
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                PointBrandLogo(height: 24)
                Text(statusText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { controller.preferences.translationEnabled },
                set: { controller.setTranslationEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(PointTheme.cobalt)
            .accessibilityIdentifier("translation-toggle")
        }
    }

    private var usageCard: some View {
        HStack(spacing: 13) {
            Text("⌥")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PointTheme.cobalt)
                .frame(width: 38, height: 38)
                .background(PointTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "Hold Left Option and hover"))
                    .font(.system(size: 13.5, weight: .semibold))
                Text(String(localized: "English and Chinese are detected automatically"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(13)
        .background(PointTheme.controlFill(colorScheme), in: RoundedRectangle(cornerRadius: 13))
    }

    private var delayControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Hover delay"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(controller.preferences.hoverDelay, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("s").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { controller.preferences.hoverDelay },
                    set: { controller.setHoverDelay($0) }
                ),
                in: 0.15...1,
                step: 0.05
            )
            .tint(PointTheme.cobalt)
            .accessibilityIdentifier("hover-delay-slider")
        }
    }

    private func capabilityRow(
        icon: String,
        title: String,
        state: PermissionState,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22)
            Text(title).font(.system(size: 12.5, weight: .medium))
            Text(String(localized: "Required"))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.orange)
            Spacer()
            if state == .granted {
                Label(String(localized: "Ready"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11.5, weight: .medium))
            } else if state == .requesting || state == .checking {
                ProgressView().controlSize(.small)
            } else {
                Button(String(localized: "Open Settings"), action: action)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(PointTheme.cobalt)
            }
        }
        .frame(height: 37)
    }

    private var languageRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "translate").frame(width: 22)
            Text(String(localized: "Built-in translation"))
                .font(.system(size: 12.5, weight: .medium))
            Spacer()
            switch languagePacks.status {
            case .installed:
                Label(String(localized: "Ready"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11.5, weight: .medium))
            case .checking, .preparing:
                ProgressView().controlSize(.small)
            case .failed:
                Button(String(localized: "Retry")) { languagePacks.retry() }
                    .controlSize(.small)
            case .unsupported:
                Text(String(localized: "Unavailable"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .frame(height: 37)
    }

    private var privacyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Online context explanation"))
                    .font(.system(size: 12.5, weight: .medium))
                Text(cloudConsentText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if controller.preferences.cloudContextConsent == .allowed {
                Button(String(localized: "Turn off")) {
                    controller.setCloudContextConsent(.denied)
                }
                .controlSize(.small)
            }
        }
        .frame(height: 43)
    }

    private var footer: some View {
        HStack {
            Text(AppConfiguration.appVersion())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(String(localized: "Quit Pointrans")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("quit-pointrans-button")
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
        .overlay(alignment: .top) { Rectangle().fill(PointTheme.hairline).frame(height: 1) }
    }

    private var statusText: String {
        switch readiness {
        case .ready: return String(localized: "Ready to translate")
        case .paused: return String(localized: "Translation is paused")
        case .needsAccessibility: return String(localized: "Accessibility is required")
        case .needsScreenCapture: return String(localized: "Screen Recording is required")
        case .preparingLanguagePack: return String(localized: "Preparing language capability…")
        case .recoveringListener: return String(localized: "Restoring text detection…")
        case .listenerFailed: return String(localized: "Text detection needs attention")
        case .onboarding: return String(localized: "Setup is required")
        case .launching: return String(localized: "Starting…")
        case .fatalStartupError: return String(localized: "Pointrans needs attention")
        }
    }

    private var statusColor: Color {
        readiness == .ready ? .green : .secondary
    }

    private var readiness: AppReadiness {
        AppReadinessResolver.resolve(
            onboardingComplete: controller.preferences.didCompleteOnboarding,
            translationEnabled: controller.preferences.translationEnabled,
            accessibilityGranted: permissions.accessibilityGranted,
            screenCaptureGranted: permissions.screenCaptureGranted,
            languagePackStatus: languagePacks.status,
            triggerRuntimeState: controller.triggerRuntimeState
        )
    }

    private var cloudConsentText: String {
        switch controller.preferences.cloudContextConsent {
        case .allowed: String(localized: "Used only when this Mac cannot explain")
        case .denied: String(localized: "Never sends text online")
        case .undecided: String(localized: "Asked only if it is needed")
        }
    }
}
