import SwiftUI
import MacFanControlCore

struct TemperatureView: View {
    let sensors: [TemperatureSensor]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temperatures")
                .font(.subheadline.weight(.semibold))

            if sensors.isEmpty {
                Text("No temperature sensors found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedSensors, id: \.component) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.component)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(group.sensors) { sensor in
                            TemperatureRow(sensor: sensor)
                        }
                    }
                }
            }
        }
    }

    private var groupedSensors: [(component: String, sensors: [TemperatureSensor])] {
        let visible = Array(sensors.prefix(10))
        let groups = Dictionary(grouping: visible, by: \.component)
        return groups.keys
            .sorted { SMCKeyCodec.componentSortOrder($0) < SMCKeyCodec.componentSortOrder($1) }
            .compactMap { component in
                guard var items = groups[component] else { return nil }
                items.sort { $0.celsius > $1.celsius }
                return (component, items)
            }
    }
}

private struct TemperatureRow: View {
    let sensor: TemperatureSensor

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(heatColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(sensor.name)
                    .font(.caption.weight(.medium))
                if sensor.name != sensor.id {
                    Text(sensor.id)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(String(format: "%.1f°C", sensor.celsius))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(heatColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sensor.name), \(String(format: "%.1f degrees", sensor.celsius))")
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
