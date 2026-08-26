import SwiftUI

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

struct PointBrandIcon: View {
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.11, green: 0.45, blue: 1), PointTheme.cobaltDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            PointGlyph(color: .white)
                .padding(size * 0.19)
        }
        .frame(width: size, height: size)
        .shadow(color: PointTheme.cobalt.opacity(0.18), radius: size * 0.12, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

struct PointGlyph: View {
    var color: Color = PointTheme.cobalt

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 36
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * scale, y: y * scale)
            }

            var letter = Path()
            letter.move(to: point(8, 30))
            letter.addLine(to: point(8, 6))
            letter.addLine(to: point(17, 6))
            letter.addCurve(to: point(27, 16), control1: point(23, 6), control2: point(27, 10))
            letter.addCurve(to: point(17, 25), control1: point(27, 22), control2: point(23, 25))
            letter.addLine(to: point(13, 25))
            context.stroke(
                letter,
                with: .color(color),
                style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round, lineJoin: .round)
            )

            var cursor = Path()
            cursor.move(to: point(20, 19))
            cursor.addLine(to: point(32, 29))
            cursor.addLine(to: point(27, 29))
            cursor.addLine(to: point(24.8, 35))
            cursor.closeSubpath()
            context.fill(cursor, with: .color(color))
        }
    }
}

struct PointMark: View {
    var size: CGFloat = 34
    var template = false

    var body: some View {
        PointGlyph(color: template ? .primary : PointTheme.cobalt)
            .frame(width: size, height: size)
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
