import AppKit
import FoundationModels
import SwiftUI
import Translation

private enum ControlCenterPage {
    case main
    case permissions
    case about
}

struct ControlCenterView: View {
    @Bindable var controller: TranslationController
    @Bindable var languagePacks: LanguagePackManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var page: ControlCenterPage = .main
    @State private var isTriggerChooserPresented = false

    var body: some View {
        ZStack {
            PointTheme.background(colorScheme).ignoresSafeArea()
            switch page {
            case .main:
                mainPage
            case .permissions:
                permissionsPage
            case .about:
                aboutPage
            }
        }
        .frame(width: 360, height: 520)
        .background {
            Color.clear
                .frame(width: 1, height: 1)
                .translationTask(languagePacks.configuration) { session in
                    await languagePacks.performPreparation(using: session)
                }
        }
        .task {
            languagePacks.refresh(direction: controller.preferences.direction)
            if !controller.preferences.didCompleteOnboarding {
                page = .permissions
            }
        }
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)

            triggerMenu
                .padding(.horizontal, 20)
                .padding(.top, 14)

            directionPicker
                .padding(.horizontal, 20)
                .padding(.top, 14)

            delayControl
                .padding(.horizontal, 20)
                .padding(.top, 13)

            sectionDivider
                .padding(.horizontal, 20)
                .padding(.top, 15)

            aiSection
                .padding(.horizontal, 20)
                .padding(.top, 13)

            sectionDivider
                .padding(.horizontal, 20)
                .padding(.top, 13)

            permissionsSummary
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Spacer(minLength: 8)
            footer
        }
        .accessibilityIdentifier("control-center-main")
    }

    private var header: some View {
        HStack(spacing: 12) {
            PointBrandIcon(size: 43)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pointrans")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(controller.preferences.translationEnabled
                     ? String(localized: "Translation is on")
                     : String(localized: "Translation is paused"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { controller.preferences.translationEnabled },
                set: { controller.setTranslationEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(PointTheme.cobalt)
            .controlSize(.regular)
            .accessibilityIdentifier("translation-toggle")
        }
    }

    private var triggerMenu: some View {
        Button {
            isTriggerChooserPresented.toggle()
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(PointTheme.surface(colorScheme))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 3, y: 1)
                    Text(controller.preferences.triggerModifier.symbol)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PointTheme.cobalt)
                }
                .frame(width: 29, height: 29)

                Text(String(
                    format: String(localized: "Hold %@ and hover"),
                    controller.preferences.triggerModifier.shortLocalizedTitle
                ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 43)
            .frame(maxWidth: .infinity)
            .background(PointTheme.controlFill(colorScheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(PointTheme.hairline, lineWidth: 0.7)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .popover(isPresented: $isTriggerChooserPresented, arrowEdge: .trailing) {
            triggerChooser
        }
        .accessibilityIdentifier("trigger-menu")
    }

    private var triggerChooser: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Trigger key"))
                .font(.system(size: 13.5, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.bottom, 3)

            ForEach(TriggerModifier.allCases, id: \.self) { modifier in
                Button {
                    controller.setTriggerModifier(modifier)
                    isTriggerChooserPresented = false
                } label: {
                    HStack(spacing: 10) {
                        Text(modifier.symbol)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(PointTheme.cobalt)
                            .frame(width: 20)
                        Text(modifier.localizedTitle)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        if modifier == controller.preferences.triggerModifier {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PointTheme.cobalt)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trigger-choice-\(modifier.rawValue)")
            }
        }
        .padding(10)
        .frame(width: 210)
        .background(PointTheme.background(colorScheme))
    }

    private var directionPicker: some View {
        HStack(spacing: 0) {
            directionButton(.englishToChinese)
            directionButton(.chineseToEnglish)
        }
        .padding(2)
        .frame(height: 45)
        .background(PointTheme.controlFill(colorScheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(PointTheme.hairline, lineWidth: 0.7)
        }
        .accessibilityIdentifier("direction-picker")
    }

    private func directionButton(_ direction: TranslationDirection) -> some View {
        let selected = controller.preferences.direction == direction
        return Button {
            controller.setDirection(direction)
            languagePacks.refresh(direction: direction)
        } label: {
            Text(direction.compactLocalizedTitle)
                .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? PointTheme.cobalt : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(PointTheme.surface(colorScheme))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.09), radius: 3, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var delayControl: some View {
        HStack(spacing: 12) {
            Text(String(localized: "Hover delay"))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .frame(width: 84, alignment: .leading)
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
            Text(controller.preferences.hoverDelay, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .frame(width: 39, alignment: .trailing)
            Text("s")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 9)
        }
        .frame(height: 31)
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "AI context"))
                .font(.system(size: 13.5, weight: .bold))
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(PointTheme.surface(colorScheme))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 4, y: 1)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PointTheme.cobalt)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(aiHeadline)
                        .font(.system(size: 13, weight: .medium))
                    Text(String(localized: "On-device first · automatic fallback"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { controller.preferences.aiEnabled },
                    set: { controller.setAIEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(PointTheme.cobalt)
                .controlSize(.small)
                .accessibilityIdentifier("ai-toggle")
            }
        }
    }

    private var permissionsSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { page = .permissions } label: {
                HStack {
                    Text(String(localized: "Permissions"))
                        .font(.system(size: 13.5, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("permissions-page-button")

            summaryPermissionRow(
                icon: "accessibility",
                title: String(localized: "Accessibility"),
                granted: controller.accessibilityGranted,
                action: controller.requestAccessibilityPermission
            )
            summaryPermissionRow(
                icon: "record.circle",
                title: String(localized: "Screen Recording"),
                granted: controller.screenCaptureGranted,
                action: controller.requestScreenCapturePermission
            )
        }
    }

    private func summaryPermissionRow(icon: String, title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if granted { page = .permissions } else { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
                StatusDot(color: granted ? .green : .orange)
                Text(granted ? String(localized: "Granted") : String(localized: "Required"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 31)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var permissionsPage: some View {
        VStack(spacing: 0) {
            subpageHeader(String(localized: "Permissions & language pack"))
                .padding(.horizontal, 20)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "Ready Pointrans"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(String(localized: "Accessibility powers the trigger and accurate text lookup. Screen Recording is used only when OCR fallback is needed."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 22)

            VStack(spacing: 0) {
                permissionDetailRow(
                    icon: "accessibility",
                    title: String(localized: "Accessibility"),
                    detail: String(localized: "Trigger and text lookup"),
                    granted: controller.accessibilityGranted,
                    action: controller.requestAccessibilityPermission
                )
                sectionDivider
                permissionDetailRow(
                    icon: "record.circle",
                    title: String(localized: "Screen Recording"),
                    detail: String(localized: "OCR fallback only"),
                    granted: controller.screenCaptureGranted,
                    action: controller.requestScreenCapturePermission
                )
                sectionDivider
                languagePackRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer()
            Button {
                controller.preferences.didCompleteOnboarding = true
                page = .main
            } label: {
                Text(String(localized: "Done"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(PointTheme.cobalt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .accessibilityIdentifier("permissions-done-button")
        }
    }

    private func permissionDetailRow(
        icon: String,
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    StatusDot(color: .green)
                    Text(String(localized: "Granted"))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            } else {
                Button(String(localized: "Enable"), action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(PointTheme.cobalt)
                    .controlSize(.small)
            }
        }
        .frame(height: 65)
    }

    private var languagePackRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PointTheme.cobalt)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "English ↔ Chinese language pack"))
                    .font(.system(size: 13, weight: .semibold))
                Text(languagePackStatusText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch languagePacks.status {
            case .available, .failed:
                Button(String(localized: "Prepare")) {
                    languagePacks.prepare(direction: controller.preferences.direction)
                }
                .buttonStyle(.borderedProminent)
                .tint(PointTheme.cobalt)
                .controlSize(.small)
            case .checking, .preparing:
                ProgressView().controlSize(.small)
            case .installed:
                StatusDot(color: .green)
            case .unsupported:
                StatusDot(color: .orange)
            }
        }
        .frame(height: 65)
    }

    private var aboutPage: some View {
        VStack(spacing: 0) {
            subpageHeader(String(localized: "About"))
                .padding(.horizontal, 20)
                .padding(.top, 18)
            Spacer()
            PointBrandIcon(size: 76)
            Text("Pointrans")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .padding(.top, 16)
            Text(String(localized: "Point. Understand."))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            Text(String(localized: "A private, native point-to-translate companion for macOS."))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)
                .padding(.top, 17)
            Text("© 2026 CuoStudio")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.top, 16)
            Spacer()
            Text("2.0.0")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 19)
        }
    }

    private func subpageHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Button { page = .main } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(PointTheme.controlFill(colorScheme), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Back"))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            PointBrandIcon(size: 28)
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button { page = .about } label: {
                Label(String(localized: "About"), systemImage: "info.circle")
                    .frame(maxWidth: .infinity)
            }
            dividerLine.frame(height: 22)
            Button { NSApp.terminate(nil) } label: {
                Label(String(localized: "Quit"), systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("q")
            Text("2.0")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(height: 50)
        .overlay(alignment: .top) { sectionDivider }
    }

    private var aiHeadline: String {
        guard controller.preferences.aiEnabled else { return String(localized: "AI context is off") }
        if let route = controller.insight?.route {
            return route == .onDevice
                ? String(localized: "Last used: On-device")
                : String(localized: "Last used: Cloud")
        }
        return SystemLanguageModel.default.availability == .available
            ? String(localized: "On-device available")
            : String(localized: "Cloud fallback on demand")
    }

    private var languagePackStatusText: String {
        switch languagePacks.status {
        case .checking: String(localized: "Checking…")
        case .installed: String(localized: "Ready on this Mac")
        case .available: String(localized: "Available to download")
        case .preparing: String(localized: "Preparing…")
        case .unsupported: String(localized: "Language pair unavailable")
        case .failed: String(localized: "Preparation failed · Try again")
        }
    }

    private var sectionDivider: some View {
        Rectangle().fill(PointTheme.hairline).frame(height: 0.7)
    }

    private var dividerLine: some View {
        Rectangle().fill(PointTheme.hairline).frame(width: 0.7)
    }
}

private extension TriggerModifier {
    var symbol: String {
        switch self {
        case .leftOption, .rightOption: "⌥"
        case .leftCommand, .rightCommand: "⌘"
        case .leftControl, .rightControl: "⌃"
        case .leftShift, .rightShift: "⇧"
        }
    }

    var shortLocalizedTitle: String {
        switch self {
        case .leftOption: String(localized: "Left Option")
        case .rightOption: String(localized: "Right Option")
        case .leftCommand: String(localized: "Left Command")
        case .rightCommand: String(localized: "Right Command")
        case .leftControl: String(localized: "Left Control")
        case .rightControl: String(localized: "Right Control")
        case .leftShift: String(localized: "Left Shift")
        case .rightShift: String(localized: "Right Shift")
        }
    }
}

private extension TranslationDirection {
    var compactLocalizedTitle: String {
        switch self {
        case .englishToChinese: String(localized: "EN → ZH")
        case .chineseToEnglish: String(localized: "ZH → EN")
        }
    }
}
