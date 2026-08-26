import AppKit
import AVFoundation
import SwiftUI

@MainActor
private final class SpeechPlayer {
    static let shared = SpeechPlayer()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        synthesizer.speak(utterance)
    }
}

struct TranslationCardView: View {
    @Bindable var controller: TranslationController
    @Environment(\.colorScheme) private var colorScheme

    private var isPinned: Bool { controller.panelMode.isPinned }
    private var request: TranslationRequest? { controller.currentRequest }
    private var base: BaseTranslation? { controller.baseTranslation }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            meaningSection
            if isPinned {
                insightSection
                pinnedFooter
            } else {
                previewFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PointTheme.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: isPinned ? 18 : 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPinned ? 18 : 17, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.17 : 0.12), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isPinned ? "translation-pinned" : "translation-preview")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 9) {
                Text(request?.word ?? String(localized: "Reading…"))
                    .font(.system(size: isPinned ? 25 : 23, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if isPinned {
                    iconButton("doc.on.doc", help: String(localized: "Copy"), identifier: "copy-result-button") {
                        copyCurrentResult()
                    }
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PointTheme.cobalt)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(String(localized: "Pinned"))
                    iconButton("xmark", help: String(localized: "Close"), identifier: "close-pinned-button") {
                        controller.closePanel()
                    }
                } else {
                    speakButton
                }
            }

            if isPinned {
                HStack(spacing: 9) {
                    if let phoneticText {
                        Text(phoneticText)
                            .font(.system(size: 13.5, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    speakButton
                    Spacer()
                }
            } else if let phoneticText {
                Text(phoneticText)
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, isPinned ? 20 : 18)
        .padding(.top, isPinned ? 17 : 15)
        .padding(.bottom, isPinned ? 13 : 12)
    }

    private var speakButton: some View {
        Button {
            if let word = request?.word {
                SpeechPlayer.shared.speak(word)
            }
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Pronounce"))
        .accessibilityIdentifier("pronounce-button")
    }

    private var meaningSection: some View {
        Group {
            if let base, !base.meanings.isEmpty || base.deviceTranslation != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if !base.meanings.isEmpty {
                        Text(base.meanings.prefix(isPinned ? 8 : 3).joined(separator: "; "))
                            .font(.system(size: isPinned ? 18 : 17, weight: .medium))
                            .lineSpacing(3)
                            .lineLimit(isPinned ? 3 : 2)
                            .textSelection(.enabled)
                    }
                    if let deviceTranslation = base.deviceTranslation,
                       !deviceTranslation.isEmpty,
                       !base.meanings.contains(deviceTranslation) {
                        Text(deviceTranslation)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(isPinned ? 2 : 1)
                            .textSelection(.enabled)
                    }
                }
            } else if isBaseLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Looking up this word…"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "No dictionary result. Prepare the language pack for device translation."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, isPinned ? 20 : 18)
        .padding(.vertical, isPinned ? 14 : 13)
        .frame(minHeight: isPinned ? 64 : 60, alignment: .topLeading)
    }

    @ViewBuilder
    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isAIAnalyzing {
                insightContainer {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "Understanding this context…"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let result = controller.insight {
                insightContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                            Text(String(localized: "Context insight"))
                                .font(.system(size: 13.5, weight: .bold))
                            Spacer()
                            Text(routeLabel(result.route))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(PointTheme.cobalt)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text(result.insight.contextualMeaning)
                                        .font(.system(size: 16, weight: .semibold))
                                    if let part = result.insight.partOfSpeech, !part.isEmpty {
                                        Text(part)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(PointTheme.cobalt)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(PointTheme.cobalt.opacity(0.09), in: Capsule())
                                    }
                                }
                                Text(result.insight.explanation)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(.primary.opacity(0.86))
                                    .fixedSize(horizontal: false, vertical: true)
                                if let translation = result.insight.contextTranslation, !translation.isEmpty {
                                    Text(translation)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                        .frame(maxHeight: 118)
                    }
                }
            } else if let failureText {
                insightContainer {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text(failureText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if controller.preferences.aiEnabled {
                Button {
                    controller.requestContextInsight()
                } label: {
                    insightContainer {
                        HStack(spacing: 9) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Context insight"))
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text(String(localized: "Explain this word in its sentence"))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(PointTheme.cobalt)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("context-insight-button")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func insightContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 73, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [PointTheme.cobalt.opacity(colorScheme == .dark ? 0.13 : 0.075), PointTheme.cobalt.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }

    private var previewFooter: some View {
        HStack(spacing: 10) {
            sourceBadge
            Spacer()
            if controller.preferences.aiEnabled {
                Button {
                    controller.requestContextInsight()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text(String(localized: "Context insight"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(PointTheme.cobalt)
                .accessibilityIdentifier("context-insight-button")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 49)
    }

    private var pinnedFooter: some View {
        HStack(spacing: 0) {
            Label(String(localized: "Local definition"), systemImage: "character.book.closed")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(PointTheme.hairline)
                .frame(width: 0.7, height: 22)
            Button {
                controller.requestContextInsight()
            } label: {
                Label(String(localized: "AI context"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.preferences.aiEnabled ? PointTheme.cobalt : .secondary)
            .disabled(!controller.preferences.aiEnabled || isAIAnalyzing)
            .accessibilityIdentifier("context-insight-button")
        }
        .font(.system(size: 12.5, weight: .semibold))
        .frame(height: 48)
        .overlay(alignment: .top) { divider }
    }

    private var sourceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: sourceIcon)
                .font(.system(size: 11, weight: .medium))
            Text(sourceLabel)
                .font(.system(size: 11.5, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.brown.opacity(colorScheme == .dark ? 0.12 : 0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconButton(_ systemName: String, help: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: systemName == "xmark" ? 13 : 14, weight: .medium))
                .foregroundStyle(systemName == "xmark" ? Color.primary : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityIdentifier(identifier)
    }

    private var phoneticText: String? {
        let value = base?.phonetic ?? base?.pinyin
        return value?.isEmpty == false ? value : nil
    }

    private var isBaseLoading: Bool {
        if case .extracting = controller.state { return true }
        return false
    }

    private var isAIAnalyzing: Bool {
        if case .enriching = controller.state { return true }
        return false
    }

    private var failureText: String? {
        guard case .failed(_, let failure) = controller.state else { return nil }
        return switch failure {
        case .quotaExhausted:
            String(localized: "Today's cloud context quota is used up. On-device analysis remains available.")
        case .aiUnavailable:
            String(localized: "Context insight is temporarily unavailable.")
        case .message(let value):
            value
        default:
            nil
        }
    }

    private var sourceLabel: String {
        switch (base?.source, controller.extraction?.source) {
        case (.appleTranslation, _): String(localized: "On-device translation")
        case (_, .ocr): String(localized: "Offline dictionary · OCR")
        default: String(localized: "Offline dictionary")
        }
    }

    private var sourceIcon: String {
        base?.source == .appleTranslation ? "iphone" : "character.book.closed"
    }

    private var divider: some View {
        Rectangle().fill(PointTheme.hairline).frame(height: 0.7)
    }

    private func routeLabel(_ route: InsightRoute) -> String {
        route == .onDevice ? String(localized: "On-device") : String(localized: "Cloud")
    }

    private func copyCurrentResult() {
        var pieces: [String] = []
        if let word = request?.word { pieces.append(word) }
        if let base { pieces.append(base.primaryText) }
        if let insight = controller.insight?.insight {
            pieces.append(insight.contextualMeaning)
            pieces.append(insight.explanation)
            if let contextTranslation = insight.contextTranslation {
                pieces.append(contextTranslation)
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(pieces.filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string)
    }
}
