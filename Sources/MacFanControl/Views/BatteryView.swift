import SwiftUI
import MacFanControlCore

struct BatteryView: View {
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Battery")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.percentLabel)
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Text(snapshot.state.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stateColor)
                    Spacer()
                    Text(snapshot.batteryWattsLabel)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(wattsColor)
                }

                ProgressView(value: progress)
                    .tint(stateColor)

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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var progress: Double {
        min(max((snapshot.percent ?? 0) / 100, 0), 1)
    }

    private var stateColor: Color {
        switch snapshot.state {
        case .charging: return .green
        case .full: return .green
        case .pluggedNotCharging: return .orange
        case .discharging: return .primary
        case .unavailable: return .secondary
        }
    }

    private var wattsColor: Color {
        guard let watts = snapshot.batteryWatts else { return .secondary }
        if watts > 0.4 { return .green }
        if watts < -0.4 { return .orange }
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
