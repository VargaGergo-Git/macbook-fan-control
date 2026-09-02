import SwiftUI
import MacFanControlCore

/// Cool slate + teal atmosphere for the menu-bar panel.
/// Heat accents use coral — not purple, cream, or terracotta defaults.
enum AppTheme {
    static let teal = Color(red: 0.12, green: 0.68, blue: 0.64)
    static let tealDeep = Color(red: 0.07, green: 0.42, blue: 0.48)
    static let ink = Color(red: 0.07, green: 0.11, blue: 0.16)
    static let calm = Color(red: 0.25, green: 0.72, blue: 0.48)
    static let warm = Color(red: 0.98, green: 0.62, blue: 0.22)
    static let heat = Color(red: 0.95, green: 0.42, blue: 0.28)

    static var panelBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.93, green: 0.96, blue: 0.97),
                Color(red: 0.88, green: 0.93, blue: 0.95),
                Color(red: 0.90, green: 0.94, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroGlow: RadialGradient {
        RadialGradient(
            colors: [teal.opacity(0.28), teal.opacity(0.08), .clear],
            center: .topTrailing,
            startRadius: 10,
            endRadius: 180
        )
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
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.tealDeep.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.ink.opacity(0.06), radius: 10, y: 3)
            )
    }
}
