import SwiftUI
import MacFanControlCore

struct TemperatureView: View {
    let sensors: [TemperatureSensor]
    let cpuPeak: Double?
    var showSensorNames: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(showSensorNames ? "All sensors" : "Temperatures")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if showSensorNames {
                    Text("\(sensors.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            SurfaceCard(padding: 10) {
                if sensors.isEmpty {
                    Text("No temperature sensors found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sensors.prefix(showSensorNames ? 12 : 4)) { sensor in
                            TemperatureRow(
                                sensor: sensor,
                                peak: sensor.component == "CPU" ? cpuPeak : nil,
                                showName: showSensorNames
                            )
                        }
                        if showSensorNames, sensors.count > 12 {
                            Text("+\(sensors.count - 12) more in diagnostics")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
    var showName: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppTheme.heatColor(celsius: sensor.celsius))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(sensor.component)
                    .font(.caption.weight(.medium))
                if showName {
                    Text(sensor.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

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
