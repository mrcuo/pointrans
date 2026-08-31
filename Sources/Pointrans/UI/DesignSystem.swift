import SwiftUI

private final class PointBrandBundleToken {}

private extension Bundle {
    static let pointransBrand = Bundle(for: PointBrandBundleToken.self)
}

enum PointTheme {
    static let cobalt = Color(red: 0.055, green: 0.38, blue: 0.98)
    static let cobaltDeep = Color(red: 0.08, green: 0.25, blue: 0.87)
    static let cobaltSoft = Color(red: 0.91, green: 0.94, blue: 1)
    static let warmBackground = Color(red: 0.982, green: 0.974, blue: 0.956)
    static let darkBackground = Color(red: 0.09, green: 0.095, blue: 0.11)
    static let hairline = Color.primary.opacity(0.105)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : warmBackground
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.145, green: 0.15, blue: 0.17)
            : Color(red: 0.997, green: 0.992, blue: 0.978)
    }

    static func controlFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }

    static func elevated(_ scheme: ColorScheme) -> Color {
        controlFill(scheme)
    }
}

struct PointBrandLogo: View {
    var height: CGFloat = 26

    var body: some View {
        Image("PointransLogo", bundle: .pointransBrand)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.3), radius: 2)
    }
}

struct PointCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(PointTheme.elevated(colorScheme), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(PointTheme.hairline, lineWidth: 0.7)
            }
    }
}
