import AppKit
import SwiftUI

struct GuidedSampleTextView: NSViewRepresentable {
    static let sentence = "She finally made a breakthrough after months of work."
    static let targetRange = (sentence as NSString).range(of: "breakthrough")

    let onTargetFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> SampleTextView {
        SampleTextView(onTargetFrameChange: onTargetFrameChange)
    }

    func updateNSView(_ nsView: SampleTextView, context: Context) {
        nsView.onTargetFrameChange = onTargetFrameChange
        nsView.updatePresentation()
        nsView.layoutSubtreeIfNeeded()
        nsView.reportTargetFrame()
    }

    @MainActor
    final class SampleTextView: NSView {
        var onTargetFrameChange: (CGRect) -> Void
        private let prefix = NSTextField(labelWithString: "She finally made a ")
        private let target = TargetWordView()
        private let suffix = NSTextField(labelWithString: " after months of work.")
        private let stack = NSStackView()

        init(onTargetFrameChange: @escaping (CGRect) -> Void) {
            self.onTargetFrameChange = onTargetFrameChange
            super.init(frame: .zero)

            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 0
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(prefix)
            stack.addArrangedSubview(target)
            stack.addArrangedSubview(suffix)
            addSubview(stack)

            for field in [prefix, suffix] {
                field.isSelectable = true
                field.maximumNumberOfLines = 1
                field.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            target.setContentCompressionResistancePriority(.required, for: .horizontal)
            target.setAccessibilityIdentifier("guided-target-word")
            target.setAccessibilityLabel(OnboardingProgressPolicy.guidedTargetWord)

            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
            ])
            updatePresentation()
        }

        required init?(coder: NSCoder) { nil }

        func updatePresentation() {
            let font = NSFont.systemFont(ofSize: 16.5, weight: .medium)
            prefix.font = font
            suffix.font = font
            prefix.textColor = .labelColor
            suffix.textColor = .labelColor
            target.updatePresentation()
        }

        override func layout() {
            super.layout()
            reportTargetFrame()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportTargetFrame()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updatePresentation()
        }

        func reportTargetFrame() {
            guard let window, target.bounds.width > 0, target.bounds.height > 0 else { return }
            let frameInWindow = target.convert(target.bounds, to: nil)
            let screenFrame = window.convertToScreen(frameInWindow)
            Task { @MainActor [onTargetFrameChange] in onTargetFrameChange(screenFrame) }
        }
    }

    @MainActor
    final class TargetWordView: NSView {
        private let label = NSTextField(labelWithString: OnboardingProgressPolicy.guidedTargetWord)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 7
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isSelectable = true
            label.maximumNumberOfLines = 1
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
                label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
            ])
            updatePresentation()
        }

        required init?(coder: NSCoder) { nil }

        func updatePresentation() {
            label.font = .systemFont(ofSize: 17, weight: .bold)
            label.textColor = .controlAccentColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.11).cgColor
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updatePresentation()
        }
    }
}
