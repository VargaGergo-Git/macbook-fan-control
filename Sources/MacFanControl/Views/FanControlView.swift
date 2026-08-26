import SwiftUI
import AppKit
import MacFanControlCore

struct FanControlView: View {
    @ObservedObject var controller: FanController
    @State private var copiedDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusBanner
                authorizationBanner

                if controller.fans.isEmpty && controller.sensors.isEmpty {
                    emptyState
                } else {
                    if !controller.fans.isEmpty {
                        fanSection
                    }
                    TemperatureView(sensors: controller.sensors)
                }

                footer
            }
            .padding(16)
            .frame(width: 360)
        }
        .frame(minWidth: 360, minHeight: 360)
        .onAppear {
            controller.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            controller.releaseAllFans()
            controller.stop()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "fanblades.fill")
                .font(.title3)
                .foregroundStyle(controller.isManualMode ? Color.orange : Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacFanControl")
                    .font(.headline)
                Text(controller.hardwareProfile?.chipDescription ?? "MacBook")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(controller.isManualMode ? "Manual" : "Automatic")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill((controller.isManualMode ? Color.orange : Color.green).opacity(0.18))
                )
                .foregroundStyle(controller.isManualMode ? Color.orange : Color.green)
        }
    }

    private var statusBanner: some View {
        Text(controller.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var authorizationBanner: some View {
        if controller.isReadOnly || controller.hardwareProfile == nil {
            EmptyView()
        } else if controller.isAuthorized {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("Fan control allowed this session")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.10))
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow fan control once")
                    .font(.subheadline.weight(.semibold))
                Text("macOS will ask for your administrator password. After that, moving the slider will not ask again until you restart the Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Allow fan control…") {
                    controller.authorize()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Looking for fans and sensors…")
                .font(.subheadline.weight(.semibold))
            Text(controller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var fanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fans")
                .font(.subheadline.weight(.semibold))

            ForEach(controller.fans) { fan in
                FanCard(fan: fan, fanCount: controller.fans.count, isManual: controller.isManualMode) { rpm in
                    controller.setFanSpeed(fanID: fan.id, rpm: rpm)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Auto") {
                    controller.setAutoMode()
                }
                .buttonStyle(.bordered)
                .disabled(controller.fans.isEmpty)

                Button("Max") {
                    controller.setMaxSpeed()
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.isManualMode ? .orange : .accentColor)
                .disabled(controller.fans.isEmpty || controller.isReadOnly)

                Spacer()

                Button("Quit") {
                    controller.releaseAllFans()
                    controller.stop()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Button(copiedDiagnostics ? "Copied diagnostics" : "Copy diagnostic info") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(controller.copyDiagnostics(), forType: .string)
                copiedDiagnostics = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedDiagnostics = false
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}

private struct FanCard: View {
    let fan: Fan
    let fanCount: Int
    let isManual: Bool
    let onSpeedChange: (Double) -> Void

    @State private var sliderValue: Double
    @State private var isEditing = false

    init(fan: Fan, fanCount: Int, isManual: Bool, onSpeedChange: @escaping (Double) -> Void) {
        self.fan = fan
        self.fanCount = fanCount
        self.isManual = isManual
        self.onSpeedChange = onSpeedChange
        _sliderValue = State(initialValue: fan.targetRPM)
    }

    private var title: String {
        fanCount == 1 ? "Cooling fan" : "Fan \(fan.id + 1)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text("Target \(formatted(sliderValue)) RPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatted(fan.actualRPM))
                        .font(.title2.monospacedDigit().weight(.semibold))
                    Text("RPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Slider(
                value: $sliderValue,
                in: range,
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        onSpeedChange(sliderValue)
                    }
                }
            )
            .tint(isManual ? Color.orange : Color.accentColor)
            .disabled(fan.maxRPM <= fan.minRPM)

            HStack {
                Text("\(formatted(fan.minRPM)) min")
                Spacer()
                Text("\(formatted(fan.maxRPM)) max")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .onChange(of: fan.targetRPM) { newValue in
            guard !isEditing else { return }
            sliderValue = newValue
        }
        .onChange(of: fan.id) { _ in
            sliderValue = fan.targetRPM
        }
    }

    private var range: ClosedRange<Double> {
        let minRPM = min(fan.minRPM, fan.maxRPM)
        let maxRPM = max(fan.minRPM, fan.maxRPM)
        if maxRPM <= minRPM {
            return 0...1
        }
        return minRPM...maxRPM
    }

    private func formatted(_ value: Double) -> String {
        let number = Int(value.rounded())
        return number.formatted(.number.grouping(.automatic))
    }
}
