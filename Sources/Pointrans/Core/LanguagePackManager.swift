import Foundation
import Observation
@preconcurrency import Translation

enum LanguagePackStatus: Equatable, Sendable {
    case checking
    case preparing
    case installed
    case unsupported
    case failed
}

@MainActor
@Observable
final class LanguagePackManager {
    private(set) var status: LanguagePackStatus = .checking {
        didSet { onChange?() }
    }
    private(set) var configuration: TranslationSession.Configuration?
    @ObservationIgnored var onChange: (() -> Void)?

    private let availability: LanguageAvailability
    private var pendingDirections: [TranslationDirection] = []
    private var activeDirection: TranslationDirection?
    private var refreshTask: Task<Void, Never>?
    private let forcedInstalled: Bool

    init(forceInstalledForTesting: Bool = false) {
        forcedInstalled = forceInstalledForTesting
        if #available(macOS 26.4, *) {
            availability = LanguageAvailability(preferredStrategy: .lowLatency)
        } else {
            availability = LanguageAvailability()
        }
        if forceInstalledForTesting { status = .installed }
    }

    var isReady: Bool { status == .installed }

    func ensureRequiredPreparation() {
        guard refreshTask == nil, configuration == nil else { return }
        beginRequiredPreparation()
    }

    func beginRequiredPreparation() {
        guard !forcedInstalled else {
            status = .installed
            return
        }
        refreshTask?.cancel()
        configuration = nil
        status = .checking
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            var missing: [TranslationDirection] = []
            for direction in TranslationDirection.allCases {
                let value = await availability.status(
                    from: Locale.Language(identifier: direction.sourceLanguage),
                    to: Locale.Language(identifier: direction.targetLanguage)
                )
                guard !Task.isCancelled else { return }
                switch value {
                case .installed:
                    break
                case .supported:
                    missing.append(direction)
                case .unsupported:
                    status = .unsupported
                    return
                @unknown default:
                    status = .unsupported
                    return
                }
            }
            pendingDirections = missing
            if missing.isEmpty {
                status = .installed
            } else {
                status = .preparing
                prepareNextDirection()
            }
        }
    }

    func retry() {
        beginRequiredPreparation()
    }

    func performPreparation(using session: TranslationSession) async {
        let expected = activeDirection
        do {
            try await session.prepareTranslation()
            guard expected == activeDirection else { return }
            if let expected {
                pendingDirections.removeAll { $0 == expected }
            }
            configuration = nil
            activeDirection = nil
            if pendingDirections.isEmpty {
                status = .installed
            } else {
                prepareNextDirection()
            }
        } catch is CancellationError {
            return
        } catch {
            guard expected == activeDirection else { return }
            configuration = nil
            activeDirection = nil
            status = .failed
        }
    }

    private func prepareNextDirection() {
        guard let direction = pendingDirections.first else {
            status = .installed
            return
        }
        activeDirection = direction
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
}
