import SwiftUI
import MacFanControlCore

struct BatteryView: View {
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Power")
                .font(.subheadline.weight(.semibold))

            SurfaceCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.percentLabel)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppTheme.ink)
                        Text(snapshot.state.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stateColor)
                        Spacer()
                        Text(snapshot.batteryWattsLabel)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(wattsColor)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(stateColor.gradient)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 7)

                    metricRow("Charge rate", snapshot.batteryWattsLabel)
                    metricRow("Adapter", snapshot.adapterLine)
                    if let system = snapshot.systemWatts {
                        metricRow("System", String(format: "%.0f W", system))
                    }
                    if let volts = snapshot.voltageVolts, let milliamps = snapshot.amperageMilliamps {
                        metricRow("Pack", String(format: "%.1f V · %.2f A", volts, milliamps / 1000))
                    }
                    if let time = snapshot.timeLabel {
                        metricRow("Time", time)
                    }
                    if let cycles = snapshot.cycleCount {
                        let health = snapshot.healthPercent.map { String(format: " · health %.0f%%", $0) } ?? ""
                        metricRow("Wear", "\(cycles) cycles\(health)")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var progress: Double {
        Swift.min(Swift.max((snapshot.percent ?? 0) / 100, 0), 1)
    }

    private var stateColor: Color {
        switch snapshot.state {
        case .charging, .full: return AppTheme.calm
        case .pluggedNotCharging: return AppTheme.warm
        case .discharging: return AppTheme.tealDeep
        case .unavailable: return .secondary
        }
    }

    private var wattsColor: Color {
        guard let watts = snapshot.batteryWatts else { return .secondary }
        if watts > 0.4 { return AppTheme.calm }
        if watts < -0.4 { return AppTheme.heat }
        return .secondary
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private var accessibilityText: String {
        var parts = ["Battery", snapshot.percentLabel, snapshot.state.label, snapshot.batteryWattsLabel]
        parts.append(snapshot.adapterLine)
        if let time = snapshot.timeLabel {
            parts.append(time)
        }
        return parts.joined(separator: ", ")
    }
}
