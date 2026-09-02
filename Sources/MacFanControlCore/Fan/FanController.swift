import Foundation
import Combine

@MainActor
public final class FanController: ObservableObject {
    @Published public private(set) var fans: [Fan] = []
    @Published public private(set) var sensors: [TemperatureSensor] = []
    @Published public private(set) var isManualMode = false
    @Published public private(set) var isReadOnly = false
    @Published public private(set) var isAuthorized = false
    @Published public private(set) var statusMessage = "Connecting to SMC..."
    @Published public private(set) var hardwareProfile: HardwareProfile?
    @Published public private(set) var controlMode: ControlMode = .appleAuto
    @Published public private(set) var thermalPressure: ThermalPressure = .unknown
    @Published public private(set) var history: [HistorySample] = []
    @Published public private(set) var cpuPeakCelsius: Double?
    @Published public private(set) var battery = BatterySnapshot()

    public init() {}

    private let smc = SMCService()
    private let pressureMonitor = ThermalPressureMonitor()
    private var pollTask: Task<Void, Never>?
    private var profile: HardwareProfile?
    private var notes: [String] = []
    private var pendingTargets: [Int: Double] = [:]
    private var isWriting = false
    private var lastWatchdog = Date.distantPast

    public var summarySensors: [TemperatureSensor] {
        TemperatureSummary.hottestByComponent(sensors)
    }


    public var helperStatusSummary: String {
        if PrivilegedSMC.canWriteDirectly {
            return "Direct root SMC writes"
        }
        if PrivilegedSMC.sessionAlive {
            return "Helper session active"
        }
        if PrivilegedSMC.helperAvailable {
            return "Helper present — authorize once"
        }
        return "Helper missing"
    }

    public var writePathSummary: String {
        if PrivilegedSMC.canWriteDirectly {
            return "Direct"
        }
        if PrivilegedSMC.sessionAlive {
            return "LaunchDaemon socket"
        }
        return "Unavailable"
    }

    public func start() {
        guard pollTask == nil else { return }
        pressureMonitor.start()
        pollTask = Task { [weak self] in
            await self?.bootstrap()
            await self?.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        pressureMonitor.stop()
        smc.close()
        PrivilegedRunner.invalidate()
    }

    public func authorize() {
        Task {
            do {
                statusMessage = "macOS will ask for your password once to install the fan helper."
                try await Task.detached {
                    try PrivilegedSMC.ensureSession()
                }.value
                isAuthorized = true
                statusMessage = "Fan helper installed. Moving the slider will not ask for a password again."
            } catch PrivilegedError.authorizationDenied {
                isAuthorized = false
                statusMessage = "Administrator authorization was canceled."
            } catch {
                isAuthorized = PrivilegedSMC.sessionAlive
                statusMessage = error.localizedDescription
            }
        }
    }

    public func releaseAllFans() {
        guard let profile else { return }

        pendingTargets = [:]
        controlMode = .appleAuto
        isManualMode = false

        do {
            try PrivilegedSMC.setAutomatic(
                modeKeys: profile.fanModeKeys,
                clearFtst: profile.hasFtstKey,
                using: smc
            )
        } catch {
            notes.append("Release on exit skipped: \(error.localizedDescription)")
        }
    }

    public func setAutoMode() {
        Task {
            guard PrivilegedSMC.sessionAlive || PrivilegedSMC.canWriteDirectly else {
                statusMessage = "Click Allow fan control first. The app will not ask for a password on Auto or Max."
                return
            }
            isWriting = true
            defer { isWriting = false }
            do {
                try await setAutomaticForAllFans()
                pendingTargets = [:]
                controlMode = .appleAuto
                isManualMode = false
                isAuthorized = PrivilegedSMC.sessionAlive || PrivilegedSMC.canWriteDirectly
                statusMessage = "Apple automatic fan control restored."
            } catch PrivilegedError.authorizationDenied {
                statusMessage = "Administrator authorization was canceled."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    public func setQuietMode() {
        setCurveMode(.quiet)
    }

    public func setBalancedMode() {
        setCurveMode(.balanced)
    }

    public func setPerformanceMode() {
        setCurveMode(.performance)
    }

    public func setMaxSpeed() {
        Task {
            guard PrivilegedSMC.sessionAlive || PrivilegedSMC.canWriteDirectly else {
                statusMessage = "Click Allow fan control first. The app will not ask for a password on Auto or Max."
                return
            }
            isWriting = true
            defer { isWriting = false }
            do {
                try await setManualSpeed(forAll: fans.map(\.maxRPM))
                controlMode = .fixedRPM
                isManualMode = true
                isAuthorized = true
                statusMessage = "All fans set to maximum."
            } catch PrivilegedError.authorizationDenied {
                statusMessage = "Administrator authorization was canceled."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    public func setFanSpeed(fanID: Int, rpm: Double) {
        Task {
            do {
                guard let profile else { return }
                guard let fan = fans.first(where: { $0.id == fanID }) else { return }

                let clamped = min(max(rpm, fan.minRPM), fan.maxRPM)
                guard PrivilegedSMC.sessionAlive || PrivilegedSMC.canWriteDirectly else {
                    statusMessage = "Click Allow fan control first. The slider will not ask for a password."
                    return
                }

                statusMessage = "Setting fan \(displayName(for: fanID)) to \(Int(clamped)) RPM..."

                isWriting = true
                try await setManualSpeed(for: fanID, rpm: clamped, profile: profile)
                pendingTargets[fanID] = clamped
                overlayPendingTargets()
                controlMode = .fixedRPM
                isManualMode = true
                isAuthorized = true
                isWriting = false

                if didEchoTarget(fanID: fanID, rpm: clamped) {
                    statusMessage = "\(displayName(for: fanID)) holding \(Int(clamped)) RPM."
                } else {
                    statusMessage = "Requested \(Int(clamped)) RPM. SMC may take a moment to follow."
                }
            } catch PrivilegedError.authorizationDenied {
                isWriting = false
                controlMode = .appleAuto
                isManualMode = false
                statusMessage = "Administrator authorization was canceled."
            } catch {
                isWriting = false
                statusMessage = error.localizedDescription
                notes.append("Fan \(fanID) write failed: \(error.localizedDescription)")
            }
        }
    }

    public func copyDiagnostics() -> String {
        var extra = notes
        extra.append("Control mode: \(controlMode.rawValue)")
        extra.append("Thermal pressure: \(thermalPressure.label)")
        if let chassis = hardwareProfile?.chassis {
            extra.append("Chassis: \(chassis.summaryLabel)")
            extra.append("Model ID: \(chassis.modelIdentifier)")
        }
        if let cpuPeakCelsius {
            extra.append(String(format: "CPU session peak: %.1f °C", cpuPeakCelsius))
        }
        extra.append("History samples: \(history.count)")
        extra.append(battery.diagnosticLine)

        let report = DiagnosticExporter.makeReport(
            profile: profile ?? HardwareProfile(
                fanCount: 0,
                fanModeKeys: [],
                hasFtstKey: false,
                chipDescription: HardwareProbe.chipDescription(),
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                chassis: ChassisProfile.detect(fanCount: 0)
            ),
            fans: fans,
            sensors: sensors,
            readOnly: isReadOnly,
            notes: extra
        )
        return report.text
    }

    private func bootstrap() async {
        do {
            try smc.open()
            let detectedProfile = try HardwareProbe.profile(using: smc)
            profile = detectedProfile
            hardwareProfile = detectedProfile
            fans = try HardwareProbe.readFans(using: smc, profile: detectedProfile)
            sensors = smc.enumerateTemperatureKeys(limit: 12)
            updateCPUPeak()
            thermalPressure = pressureMonitor.current()
            battery = BatteryReader.snapshot()
            recordHistory()
            isReadOnly = false
            isAuthorized = PrivilegedSMC.canWriteDirectly || PrivilegedSMC.sessionAlive

            if PrivilegedSMC.canWriteDirectly {
                statusMessage = "Connected. Fan writes are allowed."
            } else if isAuthorized {
                statusMessage = "Connected. Fan helper is already running — no password needed."
            } else if PrivilegedSMC.helperAvailable {
                statusMessage = "Connected. Click Allow fan control once. After that the slider will not ask for a password."
            } else {
                isReadOnly = true
                statusMessage = "Helper not found. Run: bash scripts/run.sh"
                notes.append("MacFanControlHelper not found.")
                notes.append(PrivilegedSMC.helperSearchSummary)
            }
        } catch {
            isReadOnly = true
            statusMessage = error.localizedDescription
            notes.append(error.localizedDescription)
            battery = BatteryReader.snapshot()
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            battery = BatteryReader.snapshot()
            await refreshReadings()
            if controlMode.curvePreset != nil, !isWriting {
                await applyActiveCurve()
            }
            if controlMode != .appleAuto, !isWriting {
                await maintainManualControl()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func refreshReadings() async {
        guard let profile else { return }

        do {
            fans = try HardwareProbe.readFans(using: smc, profile: profile)
            overlayPendingTargets()
            sensors = smc.refreshTemperatures(sensors)
            updateCPUPeak()
            thermalPressure = pressureMonitor.current()
            isAuthorized = PrivilegedSMC.canWriteDirectly || PrivilegedSMC.sessionAlive
            recordHistory()
            if controlMode == .appleAuto {
                isManualMode = false
            }
        } catch {
            notes.append("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func setCurveMode(_ preset: CurvePreset) {
        Task {
            guard PrivilegedSMC.sessionAlive || PrivilegedSMC.canWriteDirectly else {
                statusMessage = "Click Allow fan control first. \(preset.title) will not ask for a password after that."
                return
            }
            isWriting = true
            defer { isWriting = false }
            controlMode = ControlMode.curve(preset)
            isManualMode = true
            await applyActiveCurve()
            lastWatchdog = .distantPast
            await maintainManualControl()
            isAuthorized = true
            let chassis = hardwareProfile?.chassis ?? ChassisProfile.detect(fanCount: fans.count)
            let temp = FanCurve.hottestDieCelsius(in: sensors)
            statusMessage = FanCurve.statusMessage(preset: preset, chassis: chassis, temperature: temp)
        }
    }

    private func applyActiveCurve() async {
        guard !fans.isEmpty else { return }
        guard let preset = controlMode.curvePreset else { return }
        let chassis = hardwareProfile?.chassis ?? ChassisProfile.detect(fanCount: fans.count)
        let temperature = FanCurve.hottestDieCelsius(in: sensors) ?? 0
        for fan in fans {
            pendingTargets[fan.id] = FanCurve.targetRPM(
                temperature: temperature,
                minRPM: minRPM if False else fan.minRPM,
                maxRPM: fan.maxRPM,
                preset: preset,
                chassis: chassis
            )
        }
        overlayPendingTargets()
    }
