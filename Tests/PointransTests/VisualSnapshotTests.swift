import AppKit
import CoreGraphics
import SwiftUI
import XCTest

@MainActor
final class VisualSnapshotTests: XCTestCase {
    func testControlCenterPreviewAndPinnedRenderOffscreen() async throws {
        let suiteName = "PointransVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "didCompleteOnboarding")
        defaults.set(0.15, forKey: "hoverDelay")
        defaults.set(TranslationDirection.englishToChinese.rawValue, forKey: "translationMode")

        let preferences = AppPreferences(defaults: defaults)
        let controller = TranslationController(
            preferences: preferences,
            environment: ProviderEnvironment(
                extractor: SnapshotExtractor(),
                translator: SnapshotTranslator(),
                analyzer: SnapshotAnalyzer(),
                permissions: SnapshotPermissions()
            )
        )
        defer {
            controller.stop()
            controller.closePanel()
        }

        let languagePacks = LanguagePackManager()
        try render(
            ControlCenterView(controller: controller, languagePacks: languagePacks),
            size: CGSize(width: 360, height: 520),
            colorScheme: .light,
            name: "control-center-light"
        )

        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        controller.receive(.modifierPressed(point: point, timestamp: 1))
        try await Task.sleep(for: .milliseconds(240))
        guard case .preview = controller.panelMode else {
            return XCTFail("Fixture did not produce Preview")
        }
        try render(
            TranslationCardView(controller: controller),
            size: CGSize(width: 360, height: 210),
            colorScheme: .light,
            name: "translation-preview-light"
        )

        controller.requestContextInsight()
        try await Task.sleep(for: .milliseconds(80))
        guard case .pinned = controller.panelMode,
              controller.insight != nil else {
            return XCTFail("Fixture did not produce structured Pinned insight")
        }
        try render(
            TranslationCardView(controller: controller),
            size: CGSize(width: 420, height: 372),
            colorScheme: .dark,
            name: "translation-pinned-dark"
        )
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        colorScheme: ColorScheme,
        name: String
    ) throws {
        let root = AnyView(
            content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, colorScheme)
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 8_000, "\(name) should contain rendered UI pixels")

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let directory = ProcessInfo.processInfo.environment["POINTRANS_SNAPSHOT_OUTPUT"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try data.write(to: output.appending(path: "\(name).png"), options: .atomic)
        }
    }
}

private struct SnapshotExtractor: TextExtracting {
    func extract(
        at point: CGPoint,
        displayID: CGDirectDisplayID,
        direction: TranslationDirection
    ) async throws -> ExtractionResult {
        ExtractionResult(
            word: "pulling",
            context: "She kept pulling the thread until the knot came loose.",
            bounds: CGRect(x: point.x - 24, y: point.y - 9, width: 52, height: 19),
            confidence: 1,
            source: .accessibility
        )
    }
}

private struct SnapshotTranslator: BaseTranslating {
    func translate(
        word: String,
        context: String,
        direction: TranslationDirection
    ) async throws -> BaseTranslation {
        BaseTranslation(
            meanings: ["拉", "牵引", "抽取"],
            deviceTranslation: nil,
            phonetic: "/ˈpʊlɪŋ/",
            pinyin: nil,
            source: .dictionary
        )
    }
}

private struct SnapshotAnalyzer: ContextAnalyzing {
    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> InsightResult {
        InsightResult(
            insight: ContextInsight(
                contextualMeaning: "持续拉扯",
                partOfSpeech: "verb",
                explanation: "这里表示持续施力，把线向自己的方向移动。",
                contextTranslation: "她不断拉扯那根线，直到结松开。"
            ),
            route: .onDevice,
            remainingCloudQuota: nil,
            quotaResetAt: nil
        )
    }
}

private struct SnapshotPermissions: PermissionProviding {
    var accessibilityGranted: Bool { true }
    var screenCaptureGranted: Bool { true }
    func requestAccessibility() {}
    func requestScreenCapture() async -> Bool { true }
}
