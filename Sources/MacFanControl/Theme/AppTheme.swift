import AppKit
import SwiftUI
import MacFanControlCore

/// Teal / slate atmosphere that follows System Settings appearance.
/// Dark mode is first-class — not an afterthought wash over the light palette.
enum AppTheme {
    static let teal = adaptive(
        light: (0.12, 0.68, 0.64),
        dark: (0.32, 0.84, 0.78)
    )
    static let tealDeep = adaptive(
        light: (0.07, 0.42, 0.48),
        dark: (0.48, 0.86, 0.82)
    )
    static let ink = adaptive(
        light: (0.07, 0.11, 0.16),
        dark: (0.93, 0.96, 0.97)
    )
    static let calm = adaptive(
        light: (0.25, 0.72, 0.48),
        dark: (0.36, 0.82, 0.58)
    )
    static let warm = adaptive(
        light: (0.98, 0.62, 0.22),
        dark: (1.00, 0.72, 0.34)
    )
    static let heat = adaptive(
        light: (0.95, 0.42, 0.28),
        dark: (1.00, 0.52, 0.38)
    )

    static func panelBackground(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.11),
                    Color(red: 0.09, green: 0.12, blue: 0.14),
                    Color(red: 0.08, green: 0.11, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.96, blue: 0.97),
                Color(red: 0.88, green: 0.93, blue: 0.95),
                Color(red: 0.90, green: 0.94, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func heroGlow(for scheme: ColorScheme) -> RadialGradient {
        let strength: Double = scheme == .dark ? 0.34 : 0.28
        return RadialGradient(
            colors: [teal.opacity(strength), teal.opacity(strength * 0.3), .clear],
            center: .topTrailing,
            startRadius: 10,
            endRadius: 180
        )
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.72)
    }

    static func cardStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? teal.opacity(0.22)
            : tealDeep.opacity(0.08)
    }

    static func cardShadow(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.45)
            : ink.opacity(0.06)
    }

    static func mutedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.06)
            : Color.primary.opacity(0.04)
    }

    static func heatColor(celsius: Double) -> Color {
        switch celsius {
        case ..<55: return calm
        case ..<70: return teal
        case ..<82: return warm
        default: return heat
        }
    }

    static func pressureColor(_ pressure: ThermalPressure) -> Color {
        switch pressure {
        case .nominal: return calm
        case .moderate: return warm
        case .heavy: return heat
        case .trapping, .sleeping: return .red
        case .unknown: return .secondary
        }
    }

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let rgb = isDark ? dark : light
                return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            }
        )
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 12
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.cardFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.cardStroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 10, y: 3)
            )
    }
}
