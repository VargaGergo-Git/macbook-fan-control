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
                ForEach(sensors.prefix(8)) { sensor in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sensor.component)
                                .font(.caption.weight(.medium))
                            Text(sensor.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f°C", sensor.celsius))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }
}
