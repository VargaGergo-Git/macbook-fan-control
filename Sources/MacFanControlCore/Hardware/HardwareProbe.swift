import Foundation

enum HardwareProbe {
    static func profile(using smc: SMCService) throws -> HardwareProfile {
        let fanCount = min(Int(try smc.readUInt8(SMCConstants.fanCountKey)), SMCConstants.maxFanCount)
        var modeKeys: [String] = []

        for index in 0..<fanCount {
            let resolved = resolveModeKey(for: index, smc: smc)
            modeKeys.append(resolved)
        }

        return HardwareProfile(
            fanCount: fanCount,
            fanModeKeys: modeKeys,
            hasFtstKey: smc.keyExists(SMCConstants.ftstKey),
            chipDescription: chipDescription(),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            chassis: ChassisProfile.detect(fanCount: fanCount)
        )
    }

    static func resolveModeKey(for index: Int, smc: SMCService) -> String {
        for candidate in SMCKeyCodec.modeKeyCandidates(for: index) where smc.keyExists(candidate) {
            return candidate
        }
        return SMCKeyCodec.modeKeyCandidates(for: index)[0]
    }

    static func readFans(using smc: SMCService, profile: HardwareProfile) throws -> [Fan] {
        var fans: [Fan] = []

        for index in 0..<profile.fanCount {
            let actual = try smc.readFloatRPM(SMCKeyCodec.fanKey(prefix: "F", index: index) + "Ac")
            let target = try smc.readFloatRPM(SMCKeyCodec.fanKey(prefix: "F", index: index) + "Tg")
            let minRPM = try smc.readFloatRPM(SMCKeyCodec.fanKey(prefix: "F", index: index) + "Mn")
            let maxRPM = try smc.readFloatRPM(SMCKeyCodec.fanKey(prefix: "F", index: index) + "Mx")
            let modeValue = try smc.readUInt8(profile.fanModeKeys[index])
            let mode = FanMode(rawValue: Int(modeValue)) ?? .automatic

            fans.append(
                Fan(
                    id: index,
                    modeKey: profile.fanModeKeys[index],
                    actualRPM: actual,
                    targetRPM: target,
                    minRPM: min(max(minRPM, 0), maxRPM),
                    maxRPM: max(maxRPM, minRPM),
                    mode: mode
                )
            )
        }

        return fans
    }

    static func chipDescription() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else {
            return "Apple Silicon / Intel Mac"
        }

        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand)
    }
}

public enum DiagnosticExporter {
    public static func makeReport(
        profile: HardwareProfile,
        fans: [Fan],
        sensors: [TemperatureSensor],
        readOnly: Bool,
        notes: [String]
    ) -> DiagnosticReport {
        DiagnosticReport(
            profile: profile,
            fans: fans,
            sensorCount: sensors.count,
            readOnly: readOnly,
            notes: notes
        )
    }
}
