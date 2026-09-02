import SwiftUI
import AppKit
import MacFanControlCore

struct FanControlView: View {
    @ObservedObject var controller: FanController
    @State private var copiedDiagnostics = false
    @State private var fanSpinning = false

    private var dieTemperature: Double? {
        FanCurve.hottestDieCelsius(in: controller.sensors)
    }

    private var chassis: ChassisProfile {
        controller.hardwareProfile?.chassis
            ?? ChassisProfile.detect(fanCount: controller.fans.count)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppTheme.panelBackground.ignoresSafeArea()
            AppTheme.heroGlow
                .frame(height: 220)
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    statusBanner
                    authorizationBanner

                    if controller.fans.isEmpty && controller.sensors.isEmpty && !controller.battery.isAvailable {
                        emptyState
                    } else {
                        heroMetrics
                        presetBar
                        ThermalChartView(
                            samples: controller.history,
                            maxRPM: controller.fans.map(\.maxRPM).max() ?? 6500
                        )
                        if controller.battery.isAvailable {
                            BatteryView(snapshot: controller.battery)
                        }
                        if !controller.fans.isEmpty {
                            fanSection
                        }
                        TemperatureView(
                            sensors: controller.summarySensors,
                            cpuPeak: controller.cpuPeakCelsius
                        )
                        tipBanner
                    }

                    footer
                }
                .padding(16)
                .frame(width: 380)
            }
        }
        .frame(minWidth: 380, minHeight: 420)
        .onAppear {
            controller.start()
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                fanSpinning = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            controller.releaseAllFans()
            controller.stop()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.teal.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "fanblades.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.tealDeep)
                    .rotationEffect(.degrees(fanSpinning && controller.controlMode != .appleAuto ? 360 : 0))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MacFanControl")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(chassis.summaryLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.tealDeep.opacity(0.85))
                    .lineLimit(1)
                Text(controller.hardwareProfile?.chipDescription ?? "MacBook")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                modeChip(controller.controlMode.badgeLabel, color: modeColor)
                modeChip(controller.thermalPressure.label, color: AppTheme.pressureColor(controller.thermalPressure))
            }
        }
    }

    private var modeColor: Color {
        switch controller.controlMode {
        case .appleAuto: return AppTheme.calm
        case .quietCurve: return AppTheme.teal
        case .balancedCurve: return AppTheme.tealDeep
        case .performanceCurve, .fixedRPM: return AppTheme.heat
        }
    }

    private func modeChip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    private var heroMetrics: some View {
        SurfaceCard {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Die")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(dieTemperature.map { String(format: "%.0f°", $0) } ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.heatColor(celsius: dieTemperature ?? 40))
                        .contentTransition(.numericText())
                    if let peak = controller.cpuPeakCelsius {
                        Text(String(format: "Session peak %.0f°", peak))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(controller.fans.count == 1 ? "Fan" : "Fans")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(fanRPMLabel)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppTheme.tealDeep)
                        .contentTransition(.numericText())
                    Text("RPM")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: dieTemperature ?? 0)
        .animation(.easeInOut(duration: 0.35), value: controller.fans.map(\.actualRPM))
    }

    private var fanRPMLabel: String {
        guard let rpm = controller.fans.map(\.actualRPM).max() else { return "—" }
        return Int(rpm.rounded()).formatted(.number.grouping(.automatic))
    }

    /// Max preset only when every fan is commanded to its hardware ceiling.
    private var isHoldingMaxRPM: Bool {
        guard controller.controlMode == .fixedRPM, !controller.fans.isEmpty else { return false }
        return controller.fans.allSatisfy { fan in
            abs(fan.targetRPM - fan.maxRPM) <= max(80, fan.maxRPM * 0.02)
        }
    }

    private var presetBar: some View {
        SurfaceCard(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cooling")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    presetButton("Auto", selected: controller.controlMode == .appleAuto, tint: AppTheme.calm) {
                        controller.setAutoMode()
                    }
                    presetButton("Quiet", selected: controller.controlMode == .quietCurve, tint: AppTheme.teal) {
                        controller.setQuietMode()
                    }
                    presetButton("Balanced", selected: controller.controlMode == .balancedCurve, tint: AppTheme.tealDeep) {
                        controller.setBalancedMode()
                    }
                    presetButton("Perf", selected: controller.controlMode == .performanceCurve, tint: AppTheme.heat) {
                        controller.setPerformanceMode()
                    }
                    presetButton("Max", selected: isHoldingMaxRPM, tint: AppTheme.warm) {
                        controller.setMaxSpeed()
                    }
                }

                if let preset = controller.controlMode.curvePreset {
                    let ramp = chassis.ramp(for: preset)
                    Text(String(
                        format: "%@: ramp %.0f→%.0f °C on %@",
                        preset.title,
                        ramp.start,
                        ramp.end,
                        chassis.kind.shortLabel
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: controller.controlMode)
    }

    private func presetButton(
        _ title: String,
        selected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? tint.opacity(0.18) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? tint.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .foregroundStyle(selected ? tint : .primary)
        }
        .buttonStyle(.plain)
        .disabled(controller.fans.isEmpty || !controller.isAuthorized)
        .opacity(controller.fans.isEmpty || !controller.isAuthorized ? 0.45 : 1)
    }

    private var tipBanner: some View {
        Text(chassis.kind.tip)
            .font(.caption2)
            .foregroundStyle(AppTheme.tealDeep.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.teal.opacity(0.10))
            )
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
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AppTheme.calm)
                    .font(.caption)
                Text("Helper installed — presets and slider stay unlocked")
                    .font(.caption2.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.calm.opacity(0.12))
            )
        } else {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow fan control once")
                        .font(.subheadline.weight(.semibold))
                    Text("macOS asks for your administrator password to install a small helper. After that, Auto, Quiet, Balanced, Performance, Max, and the slider will not ask again — on Air and Pro alike.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Allow fan control…") {
                        controller.authorize()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.tealDeep)
                    .controlSize(.small)
                }
            }
        }
    }

    private var emptyState: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking for fans and sensors…")
                    .font(.subheadline.weight(.semibold))
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fanSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.fans.count == 1 ? "Cooling fan" : "Fans")
                .font(.subheadline.weight(.semibold))

            ForEach(controller.fans) { fan in
                FanCard(
                    fan: fan,
                    fanCount: controller.fans.count,
                    isManual: controller.controlMode != .appleAuto,
                    isEnabled: controller.isAuthorized
                ) { rpm in
                    controller.setFanSpeed(fanID: fan.id, rpm: rpm)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
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

            Spacer()

            Button("Quit") {
                controller.releaseAllFans()
                controller.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .controlSize(.small)
        }
    }
}

private struct FanCard: View {
    let fan: Fan
    let fanCount: Int
    let isManual: Bool
    let isEnabled: Bool
    let onSpeedChange: (Double) -> Void

    @State private var sliderValue: Double
    @State private var isEditing = false

    init(
        fan: Fan,
        fanCount: Int,
        isManual: Bool,
        isEnabled: Bool,
        onSpeedChange: @escaping (Double) -> Void
    ) {
        self.fan = fan
        self.fanCount = fanCount
        self.isManual = isManual
        self.isEnabled = isEnabled
        self.onSpeedChange = onSpeedChange
        _sliderValue = State(initialValue: fan.targetRPM)
    }

    private var title: String {
        fanCount == 1 ? "Cooling fan" : "Fan \(fan.id + 1)"
    }

    var body: some View {
        SurfaceCard {
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
                            .foregroundStyle(AppTheme.tealDeep)
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
                .tint(isManual ? AppTheme.heat : AppTheme.teal)
                .disabled(!isEnabled || fan.maxRPM <= fan.minRPM)

                HStack {
                    Text("\(formatted(fan.minRPM)) min")
                    Spacer()
                    Text("\(formatted(fan.maxRPM)) max")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
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
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
}
