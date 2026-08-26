import SwiftUI
import AppKit
import MacFanControlCore

struct FanControlView: View {
    @ObservedObject var controller: FanController
    @State private var copiedDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusBanner

                if controller.fans.isEmpty {
                    emptyState
                } else {
                    fanSection
                    TemperatureView(sensors: controller.sensors)
                }

                footer
            }
            .padding(16)
            .frame(width: 340)
        }
        .frame(minWidth: 340, minHeight: 320)
        .onAppear {
            controller.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            controller.releaseAllFans()
            controller.stop()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MacFanControl")
                    .font(.headline)
                Text(controller.isManualMode ? "Manual" : "Automatic")
                    .font(.caption)
                    .foregroundStyle(controller.isManualMode ? .orange : .green)
            }
            Spacer()
        }
    }

    private var statusBanner: some View {
        Text(controller.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SMC unavailable")
                .font(.subheadline.weight(.semibold))
            Text(controller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Try quitting and relaunching the app. Fan writes require your admin password.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private var fanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans")
                .font(.subheadline.weight(.semibold))

            ForEach(controller.fans) { fan in
                FanCard(fan: fan) { rpm in
                    controller.setFanSpeed(fanID: fan.id, rpm: rpm)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button("Auto") {
                    controller.setAutoMode()
                }
                .buttonStyle(.bordered)

                Button("Max") {
                    controller.setMaxSpeed()
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.fans.isEmpty || controller.isReadOnly)
            }

            Button(copiedDiagnostics ? "Copied!" : "Copy diagnostic info") {
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
    let onSpeedChange: (Double) -> Void

    @State private var sliderValue: Double

    init(fan: Fan, onSpeedChange: @escaping (Double) -> Void) {
        self.fan = fan
        self.onSpeedChange = onSpeedChange
        _sliderValue = State(initialValue: fan.targetRPM)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fan \(fan.id)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(fan.actualRPM)) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: $sliderValue,
                in: fan.minRPM...fan.maxRPM,
                onEditingChanged: { editing in
                    if !editing {
                        onSpeedChange(sliderValue)
                    }
                }
            )

            HStack {
                Text("\(Int(fan.minRPM)) min")
                Spacer()
                Text("\(Int(fan.maxRPM)) max")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .onChange(of: fan.targetRPM) { newValue in
            sliderValue = newValue
        }
        .onTapGesture {
            onSpeedChange(sliderValue)
        }
    }
}
