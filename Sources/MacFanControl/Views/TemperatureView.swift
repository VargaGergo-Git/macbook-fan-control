import SwiftUI
import MacFanControlCore

struct TemperatureView: View {
    let sensors: [TemperatureSensor]
    let cpuPeak: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temperatures")
                .font(.subheadline.weight(.semibold))

            if sensors.isEmpty {
                Text("No temperature sensors found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sensors) { sensor in
                    TemperatureRow(sensor: sensor, peak: sensor.component == "CPU" ? cpuPeak : nil)
                }
            }
        }
    }
}

private struct TemperatureRow: View {
    let sensor: TemperatureSensor
    let peak: Double?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(heatColor)
                .frame(width: 7, height: 7)

            Text(sensor.component)
                .font(.caption.weight(.medium))

            Spacer()

            if let peak {
                Text(String(format: "Peak %.0f°", peak))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(String(format: "%.1f°C", sensor.celsius))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(heatColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let peak {
            return "\(sensor.component), \(String(format: \"%.1f degrees\", sensor.celsius)), session peak \(String(format: \"%.0f degrees\", peak))"
        }
        return "\(sensor.component), \(String(format: \"%.1f degrees\", sensor.celsius))"
    }

    private var heatColor: Color {
        switch sensor.celsius {
        case ..<60:
            return .green
        case ..<80:
            return .orange
        default:
            return .red
        }
    }
}
