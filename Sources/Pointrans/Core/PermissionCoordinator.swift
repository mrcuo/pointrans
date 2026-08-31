import Foundation
import Observation

@MainActor
@Observable
final class PermissionCoordinator {
    private(set) var accessibility: PermissionState = .unknown
    private(set) var screenCapture: PermissionState = .unknown

    @ObservationIgnored var onChange: (() -> Void)?

    private let provider: any PermissionProviding
    private var accessibilityRequest: Task<Void, Never>?
    private var screenCaptureRequest: Task<Void, Never>?

    init(provider: any PermissionProviding) {
        self.provider = provider
    }

    var accessibilityGranted: Bool { accessibility == .granted }
    var screenCaptureGranted: Bool { screenCapture == .granted }
    var allRequiredGranted: Bool { accessibilityGranted && screenCaptureGranted }

    func refresh() {
        accessibility = provider.accessibilityGranted ? .granted : normalizedMissing(accessibility)
        screenCapture = provider.screenCaptureGranted ? .granted : normalizedMissing(screenCapture)
        onChange?()
    }

    func requestAccessibility() {
        guard accessibilityRequest == nil, !accessibilityGranted else { return }
        accessibility = .requesting
        onChange?()
        accessibilityRequest = Task { [weak self] in
            guard let self else { return }
            let granted = await provider.requestAccessibility()
            guard !Task.isCancelled else { return }
            self.accessibility = granted || provider.accessibilityGranted ? .granted : .denied
            self.accessibilityRequest = nil
            self.onChange?()
        }
    }

    func requestScreenCapture() {
        guard screenCaptureRequest == nil, !screenCaptureGranted else { return }
        screenCapture = .requesting
        onChange?()
        screenCaptureRequest = Task { [weak self] in
            guard let self else { return }
            let systemAccepted = await provider.requestScreenCapture()
            guard !Task.isCancelled else { return }
            if provider.screenCaptureGranted {
                self.screenCapture = .granted
            } else {
                self.screenCapture = systemAccepted ? .restartRequired : .denied
            }
            self.screenCaptureRequest = nil
            self.onChange?()
        }
    }

    func stop() {
        accessibilityRequest?.cancel()
        screenCaptureRequest?.cancel()
        accessibilityRequest = nil
        screenCaptureRequest = nil
    }

    private func normalizedMissing(_ current: PermissionState) -> PermissionState {
        switch current {
        case .requesting: .requesting
        case .denied, .restartRequired: current
        case .unknown, .checking, .notGranted, .granted: .notGranted
        }
    }
}
