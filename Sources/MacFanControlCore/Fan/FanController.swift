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
        pollTask?.cancel()
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
            try PrivilegedRunner.withAuthorization {
                if profile.hasFtstKey {
                    try? smc.writeUInt8(SMCConstants.ftstKey, value: 0)
                }

                for index in 0..<profile.fanCount {
                    let modeKey = profile.fanModeKeys[index]
                    try smc.writeUInt8(modeKey, value: UInt8(FanMode.automatic.rawValue))
                }
            }
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
                try await setManualSpeed(for: fanID, rpm: clamped, profile: profile)
                isManualMode = true
                statusMessage = "Fan \(fanID) target set to \(Int(clamped)) RPM."
            } catch {
                statusMessage = error.localizedDescription
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
            sensors = smc.enumerateTemperatureKeys()
            isReadOnly = false
            statusMessage = "Connected. \(detectedProfile.fanCount) fan(s) detected."
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
            sensors = smc.enumerateTemperatureKeys(limit: 12)
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

        try PrivilegedRunner.withAuthorization {
            if profile.hasFtstKey {
                try? smc.writeUInt8(SMCConstants.ftstKey, value: 0)
            }

            for index in 0..<profile.fanCount {
                try smc.writeUInt8(profile.fanModeKeys[index], value: UInt8(FanMode.automatic.rawValue))
            }
        }
    }

    private func setManualSpeed(forAll rpms: [Double]) async throws {
        guard let profile else { return }

        for (index, rpm) in rpms.enumerated() where index < profile.fanCount {
            try await setManualSpeed(for: index, rpm: rpm, profile: profile)
        }
    }

    private func setManualSpeed(for fanIndex: Int, rpm: Double, profile: HardwareProfile) async throws {
        try PrivilegedRunner.withAuthorization {
            try unlockManualControlSync(for: fanIndex, profile: profile)

            let targetKey = SMCKeyCodec.fanKey(prefix: "F", index: fanIndex) + "Tg"
            try smc.writeFloatRPM(targetKey, value: rpm)
        }
    }

    private func unlockManualControl(for fanIndex: Int, profile: HardwareProfile) async throws {
        try PrivilegedRunner.withAuthorization {
            try unlockManualControlSync(for: fanIndex, profile: profile)
        }
    }

    private func unlockManualControlSync(for fanIndex: Int, profile: HardwareProfile) throws {
        let modeKey = profile.fanModeKeys[fanIndex]
        let manualValue = UInt8(FanMode.manual.rawValue)

        try smc.writeUInt8(modeKey, value: manualValue)
        if try smc.readUInt8(modeKey) == manualValue {
            return
        }

        guard profile.hasFtstKey else {
            throw SMCError.writeFailed(modeKey, status: 0x82)
        }

        try smc.writeUInt8(SMCConstants.ftstKey, value: 1)

        for _ in 0..<100 {
            try smc.writeUInt8(modeKey, value: manualValue)
            if try smc.readUInt8(modeKey) == manualValue {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw SMCError.writeFailed(modeKey, status: 0x82)
    }
}
