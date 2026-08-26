import Foundation

enum FanWriteOperations {
    static func setManualRPM(
        smc: SMCService,
        modeKey: String,
        targetKey: String,
        rpm: Double,
        useFtst: Bool
    ) throws {
        try unlockManualControl(smc: smc, modeKey: modeKey, useFtst: useFtst)
        try smc.writeFloatRPM(targetKey, value: rpm)

        let readBack = try smc.readFloatRPM(targetKey)
        if abs(readBack - rpm) <= max(100, rpm * 0.05) {
            return
        }

        // Some MacBooks accept target RPM only after a target-first write sequence.
        try smc.writeFloatRPM(targetKey, value: rpm)
        try unlockManualControl(smc: smc, modeKey: modeKey, useFtst: useFtst)
        try smc.writeFloatRPM(targetKey, value: rpm)
    }

    static func unlockManualControl(
        smc: SMCService,
        modeKey: String,
        useFtst: Bool
    ) throws {
        let manualValue = UInt8(FanMode.manual.rawValue)

        try smc.writeUInt8(modeKey, value: manualValue)
        if try smc.readUInt8(modeKey) == manualValue {
            return
        }

        guard useFtst else {
            return
        }

        try smc.writeUInt8(SMCConstants.ftstKey, value: 1)

        for _ in 0..<20 {
            try smc.writeUInt8(modeKey, value: manualValue)
            if try smc.readUInt8(modeKey) == manualValue {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    static func setAutomatic(
        smc: SMCService,
        modeKeys: [String],
        clearFtst: Bool
    ) throws {
        if clearFtst {
            try? smc.writeUInt8(SMCConstants.ftstKey, value: 0)
        }

        for modeKey in modeKeys {
            try smc.writeUInt8(modeKey, value: UInt8(FanMode.automatic.rawValue))
        }
    }
}
