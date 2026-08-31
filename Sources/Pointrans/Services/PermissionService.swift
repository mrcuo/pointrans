@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

struct PermissionService: PermissionProviding, Sendable {
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var screenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }

    func requestAccessibility() async -> Bool {
        // Avoid referencing the imported mutable global constant under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenCapture() async -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
