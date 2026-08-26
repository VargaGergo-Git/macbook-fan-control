import Foundation
import Combine

@MainActor
public final class FanController: ObservableObject {
    @Published public private(set) var fans: [Fan] = []
    @Published public private(set) var sensors: [TemperatureSensor] = []
    @Published public private(set) var isManualMode = false
    @Published public private(set) var isReadOnly = false
    @Published public private(set) var statusMessage = "Connecting to SMC..."
    @Published public private(set) var hardwareProfile: HardwareProfile?

    public init() {}

    private let smc = SMCService()
    private var pollTask: Task<Void, Never>?
    private var profile: HardwareProfile?
    private var notes: [String] = []

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

    public func releaseAllFans() {
        guard let profile else { return }

        do {
            try PrivilegedSMC.setAutomatic(
                modeKeys: profile.fanModeKeys,
                clearFtst: profile.hasFtstKey,
                using: smc
            )
        } catch {
            notes.append("Release on exit failed: \(error.localizedDescription)")
        }

        isManualMode = false
    }

    public func setAutoMode() {
        Task {
            do {
                try await setAutomaticForAllFans()
                isManualMode = false
                statusMessage = "Automatic fan control restored."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    public func setMaxSpeed() {
        Task {
            do {
                try await setManualSpeed(forAll: fans.map(\.maxRPM))
                isManualMode = true
                statusMessage = "All fans set to maximum."
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
                statusMessage = "Requesting administrator access..."
                try await setManualSpeed(for: fanID, rpm: clamped, profile: profile)
                try verifyManualWrite(for: fanID, rpm: clamped, profile: profile)
                isManualMode = true
                statusMessage = "Fan \(fanID) target set to \(Int(clamped)) RPM."
            } catch PrivilegedError.authorizationDenied {
                isManualMode = false
                statusMessage = "Administrator authorization was canceled."
            } catch {
                isManualMode = false
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

            if PrivilegedSMC.canWriteDirectly {
                statusMessage = "Connected. \(detectedProfile.fanCount) fan(s) detected."
            } else if PrivilegedSMC.helperAvailable {
                statusMessage = "Connected. \(detectedProfile.fanCount) fan(s). Move a slider to authorize fan control."
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
            if isManualMode {
                await maintainManualControl()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func refreshReadings() async {
        guard let profile else { return }

        do {
            fans = try HardwareProbe.readFans(using: smc, profile: profile)
            sensors = smc.refreshTemperatures(sensors)
        } catch {
            notes.append("Refresh failed: \(error.localizedDescription)")
        }
    }

    private func maintainManualControl() async {
        guard let profile else { return }

        for fan in fans where fan.mode != .manual {
            do {
                try await unlockManualControl(for: fan.id, profile: profile)
            } catch {
                notes.append("Watchdog unlock failed for fan \(fan.id): \(error.localizedDescription)")
            }
        }
    }

    private func setAutomaticForAllFans() async throws {
        guard let profile else { return }

        try PrivilegedSMC.setAutomatic(
            modeKeys: profile.fanModeKeys,
            clearFtst: profile.hasFtstKey,
            using: smc
        )
    }

    private func setManualSpeed(forAll rpms: [Double]) async throws {
        guard let profile else { return }

        for (index, rpm) in rpms.enumerated() where index < profile.fanCount {
            try await setManualSpeed(for: index, rpm: rpm, profile: profile)
        }
    }

    private func setManualSpeed(for fanIndex: Int, rpm: Double, profile: HardwareProfile) async throws {
        let modeKey = profile.fanModeKeys[fanIndex]
        let targetKey = SMCKeyCodec.fanKey(prefix: "F", index: fanIndex) + "Tg"

        try PrivilegedSMC.setManualRPM(
            modeKey: modeKey,
            targetKey: targetKey,
            rpm: rpm,
            useFtst: profile.hasFtstKey,
            using: smc
        )
    }

    private func unlockManualControl(for fanIndex: Int, profile: HardwareProfile) async throws {
        let modeKey = profile.fanModeKeys[fanIndex]
        try PrivilegedSMC.unlockManualControl(
            modeKey: modeKey,
            useFtst: profile.hasFtstKey,
            using: smc
        )
    }

    private func verifyManualWrite(for fanIndex: Int, rpm: Double, profile: HardwareProfile) throws {
        let modeKey = profile.fanModeKeys[fanIndex]
        let targetKey = SMCKeyCodec.fanKey(prefix: "F", index: fanIndex) + "Tg"
        let mode = try smc.readUInt8(modeKey)
        let target = try smc.readFloatRPM(targetKey)

        guard mode == UInt8(FanMode.manual.rawValue) else {
            throw SMCError.writeFailed(modeKey, smcResult: mode)
        }

        guard abs(target - rpm) <= max(150, rpm * 0.08) else {
            throw SMCError.writeFailed(targetKey, smcResult: 0)
        }
    }
}
