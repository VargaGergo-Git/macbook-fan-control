import SwiftUI
import MacFanControlCore

struct TemperatureView: View {
    let sensors: [TemperatureSensor]
    let cpuPeak: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temperatures")
                .font(.subheadline.weight(.semibold))

            SurfaceCard(padding: 10) {
                if sensors.isEmpty {
                    Text("No temperature sensors found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sensors) { sensor in
                            TemperatureRow(
                                sensor: sensor,
                                peak: sensor.component == "CPU" ? cpuPeak : nil
                            )
                        }
                    }
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
                .fill(AppTheme.heatColor(celsius: sensor.celsius))
                .frame(width: 8, height: 8)

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
                .foregroundStyle(AppTheme.heatColor(celsius: sensor.celsius))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let current = String(format: "%.1f degrees", sensor.celsius)
        if let peak {
            let peakText = String(format: "%.0f degrees", peak)
            return "\(sensor.component), \(current), session peak \(peakText)"
        }
        return "\(sensor.component), \(current)"
    }
}
