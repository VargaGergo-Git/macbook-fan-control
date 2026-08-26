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

    public init() {}

    private let smc = SMCService()
    private var pollTask: Task<Void, Never>?
    private var profile: HardwareProfile?
    private var notes: [String] = []
    private var pendingTargets: [Int: Double] = [:]
    private var isWriting = false
    private var lastWatchdog = Date.distantPast

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.bootstrap()
            await self?.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
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
                isManualMode = false
                isAuthorized = PrivilegedSMC.sessionAlive || PrivilegedSMC.canWriteDirectly
                statusMessage = "Automatic fan control restored."
            } catch PrivilegedError.authorizationDenied {
                statusMessage = "Administrator authorization was canceled."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
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
        let report = DiagnosticExporter.makeReport(
            profile: profile ?? HardwareProfile(
                fanCount: 0,
                fanModeKeys: [],
                hasFtstKey: false,
                chipDescription: HardwareProbe.chipDescription(),
                macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            fans: fans,
            sensors: sensors,
            readOnly: isReadOnly,
            notes: notes
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
                statusMessage = "Helper not found. Run: swift build -c release && ./scripts/run.sh"
                notes.append("MacFanControlHelper not found.")
                notes.append(PrivilegedSMC.helperSearchSummary)
            }
        } catch {
            isReadOnly = true
            statusMessage = error.localizedDescription
            notes.append(error.localizedDescription)
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refreshReadings()
            if isManualMode, !isWriting {
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
            isAuthorized = PrivilegedSMC.canWriteDirectly || PrivilegedSMC.sessionAlive
            if pendingTargets.isEmpty, !isManualMode {
                isManualMode = fans.contains { $0.mode == .manual }
            }
        } catch {
            notes.append("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func maintainManualControl() async {
        guard let profile else { return }
        guard PrivilegedSMC.sessionAlive || PrivilegedSMC.canWriteDirectly else { return }
        guard !pendingTargets.isEmpty else { return }
        guard Date().timeIntervalSince(lastWatchdog) >= 1 else { return }
        lastWatchdog = Date()

        for (fanIndex, rpm) in pendingTargets {
            do {
                try await setManualSpeed(for: fanIndex, rpm: rpm, profile: profile)
            } catch {
                notes.append("Watchdog write failed for fan \(fanIndex): \(error.localizedDescription)")
            }
        }
    }

    private func setAutomaticForAllFans() async throws {
        guard let profile else { return }

        if PrivilegedSMC.canWriteDirectly {
            try PrivilegedSMC.setAutomatic(
                modeKeys: profile.fanModeKeys,
                clearFtst: profile.hasFtstKey,
                using: smc
            )
            return
        }

        try await Task.detached {
            try PrivilegedSMC.setAutomatic(
                modeKeys: profile.fanModeKeys,
                clearFtst: profile.hasFtstKey
            )
        }.value
    }

    private func setManualSpeed(forAll rpms: [Double]) async throws {
        guard let profile else { return }

        for (index, rpm) in rpms.enumerated() where index < profile.fanCount {
            try await setManualSpeed(for: index, rpm: rpm, profile: profile)
            pendingTargets[index] = rpm
        }
        overlayPendingTargets()
    }

    private func setManualSpeed(
        for fanIndex: Int,
        rpm: Double,
        profile: HardwareProfile
    ) async throws {
        let modeKey = profile.fanModeKeys[fanIndex]
        let targetKey = SMCKeyCodec.fanKey(prefix: "F", index: fanIndex) + "Tg"

        if PrivilegedSMC.canWriteDirectly {
            try PrivilegedSMC.setManualRPM(
                modeKey: modeKey,
                targetKey: targetKey,
                rpm: rpm,
                useFtst: profile.hasFtstKey,
                using: smc
            )
            return
        }

        try await Task.detached {
            try PrivilegedSMC.setManualRPM(
                modeKey: modeKey,
                targetKey: targetKey,
                rpm: rpm,
                useFtst: profile.hasFtstKey
            )
        }.value
    }

    private func overlayPendingTargets() {
        guard !pendingTargets.isEmpty else { return }

        for index in fans.indices {
            if let target = pendingTargets[fans[index].id] {
                fans[index].targetRPM = target
                fans[index].mode = .manual
            }
        }
        isManualMode = true
    }

    private func didEchoTarget(fanID: Int, rpm: Double) -> Bool {
        guard let fan = fans.first(where: { $0.id == fanID }) else { return false }
        let key = SMCKeyCodec.fanKey(prefix: "F", index: fanID) + "Tg"
        guard let echoed = try? smc.readFloatRPM(key) else { return false }
        return abs(echoed - rpm) <= max(150, rpm * 0.08) || abs(fan.actualRPM - rpm) <= max(200, rpm * 0.1)
    }

    private func displayName(for fanID: Int) -> String {
        fans.count == 1 ? "Fan" : "Fan \(fanID + 1)"
    }
}
