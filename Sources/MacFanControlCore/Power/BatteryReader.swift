import Foundation
#if os(macOS)
import IOKit
#endif

enum BatteryReader {
    static func snapshot() -> BatterySnapshot {
        #if os(macOS)
        return readSmartBattery() ?? BatterySnapshot(state: .unavailable)
        #else
        return BatterySnapshot(state: .unavailable)
        #endif
    }

    #if os(macOS)
    private static func readSmartBattery() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let adapter = dictionary(properties["AdapterDetails"])
        let telemetry = dictionary(properties["PowerTelemetryData"])

        let currentCapacity = double(properties["AppleRawCurrentCapacity"]) ?? double(properties["CurrentCapacity"])
        let maxCapacity = double(properties["AppleRawMaxCapacity"]) ?? double(properties["MaxCapacity"])
        let designCapacity = double(properties["DesignCapacity"])
        let percent: Double?
        if let currentCapacity, let maxCapacity {
            percent = BatteryMath.percent(current: currentCapacity, maximum: maxCapacity)
        } else {
            percent = nil
        }

        let isCharging = bool(properties["IsCharging"])
        let isPluggedIn = bool(properties["ExternalConnected"])
        let isFull = bool(properties["FullyCharged"])
        let state: BatteryChargeState
        if isFull, isPluggedIn, !isCharging {
            state = .full
        } else {
            state = BatteryMath.state(isCharging: isCharging, isPluggedIn: isPluggedIn, percent: percent)
        }

        let milliamps = int64(properties["InstantAmperage"]).map(BatteryMath.milliamps)
            ?? int64(properties["Amperage"]).map(BatteryMath.milliamps)
        let volts = (double(properties["Voltage"]) ?? double(adapter["AdapterVoltage"])).map(BatteryMath.volts)
        let telemetryBattery = double(telemetry["BatteryPower"]).map(BatteryMath.wattsFromTelemetry)
        let batteryWatts = BatteryMath.batteryWatts(
            isCharging: isCharging,
            milliamps: milliamps,
            volts: volts,
            telemetryWatts: telemetryBattery
        )

        let adapterLive = double(telemetry["SystemPowerIn"]).map(BatteryMath.wattsFromTelemetry)
            ?? double(properties["AdapterPower"]).map(BatteryMath.wattsFromTelemetry)
        let adapterLimit = double(adapter["Watts"]) ?? double(properties["AdapterWatts"])
        let systemWatts = double(telemetry["SystemLoad"]).map(BatteryMath.wattsFromTelemetry)

        let timeToFull = BatteryMath.sanitizedMinutes(int(properties["AvgTimeToFull"]))
        let timeToEmpty = BatteryMath.sanitizedMinutes(int(properties["TimeRemaining"]))
            ?? BatteryMath.sanitizedMinutes(int(properties["AvgTimeToEmpty"]))
        let minutes: Int?
        switch state {
        case .charging:
            minutes = timeToFull
        case .discharging:
            minutes = timeToEmpty
        default:
            minutes = nil
        }

        return BatterySnapshot(
            percent: percent,
            state: state,
            batteryWatts: batteryWatts,
            adapterWatts: adapterLive,
            adapterLimitWatts: adapterLimit,
            systemWatts: systemWatts,
            voltageVolts: volts,
            amperageMilliamps: milliamps,
            minutesRemaining: minutes,
            cycleCount: int(properties["CycleCount"]),
            healthPercent: BatteryMath.healthPercent(maximum: maxCapacity ?? 0, design: designCapacity ?? 0)
        )
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private static func bool(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let number = value as? Int { return number }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let number = value as? Int64 { return number }
        if let number = value as? Int { return Int64(number) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? Int64 { return Double(number) }
        return nil
    }
    #endif
}
