import Foundation
import Observation
@preconcurrency import Translation

enum LanguagePackStatus: Equatable, Sendable {
    case checking
    case installed
    case available
    case preparing
    case unsupported
    case failed
}

@MainActor
@Observable
final class LanguagePackManager {
    private(set) var status: LanguagePackStatus = .checking
    private(set) var configuration: TranslationSession.Configuration?
    private let availability: LanguageAvailability
    private var activeDirection: TranslationDirection?
    private var refreshTask: Task<Void, Never>?

    init() {
        if #available(macOS 26.4, *) {
            availability = LanguageAvailability(preferredStrategy: .lowLatency)
        } else {
            availability = LanguageAvailability()
        }
    }

    func refresh(direction: TranslationDirection) {
        activeDirection = direction
        configuration = nil
        refreshTask?.cancel()
        status = .checking
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let source = Locale.Language(identifier: direction.sourceLanguage)
            let target = Locale.Language(identifier: direction.targetLanguage)
            let value = await availability.status(from: source, to: target)
            guard !Task.isCancelled, activeDirection == direction else { return }
            status = switch value {
            case .installed: .installed
            case .supported: .available
            case .unsupported: .unsupported
            @unknown default: .unsupported
            }
        }
    }

    func prepare(direction: TranslationDirection) {
        activeDirection = direction
        refreshTask?.cancel()
        status = .preparing
        if #available(macOS 26.4, *) {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: direction.sourceLanguage),
                target: Locale.Language(identifier: direction.targetLanguage),
                preferredStrategy: .lowLatency
            )
        } else {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: direction.sourceLanguage),
                target: Locale.Language(identifier: direction.targetLanguage)
            )
        }
        configuration?.invalidate()
    }

    func performPreparation(using session: TranslationSession) async {
        let expectedDirection = activeDirection
        do {
            try await session.prepareTranslation()
            guard expectedDirection == activeDirection else { return }
            status = .installed
            configuration = nil
        } catch is CancellationError {
            guard expectedDirection == activeDirection else { return }
            status = .available
        } catch {
            guard expectedDirection == activeDirection else { return }
            status = .failed
        }
    }
}
