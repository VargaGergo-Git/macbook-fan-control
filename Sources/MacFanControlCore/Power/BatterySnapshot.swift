import Foundation

public enum BatteryChargeState: String, Sendable, Equatable {
    case charging
    case discharging
    case full
    case pluggedNotCharging
    case unavailable

    public var label: String {
        switch self {
        case .charging: return "Charging"
        case .discharging: return "On battery"
        case .full: return "Full"
        case .pluggedNotCharging: return "Plugged, not charging"
        case .unavailable: return "No battery"
        }
    }
}

public struct BatterySnapshot: Sendable, Equatable {
    public var percent: Double?
    public var state: BatteryChargeState
    public var batteryWatts: Double?
    public var adapterWatts: Double?
    public var adapterLimitWatts: Double?
    public var systemWatts: Double?
    public var voltageVolts: Double?
    public var amperageMilliamps: Double?
    public var minutesRemaining: Int?
    public var cycleCount: Int?
    public var healthPercent: Double?

    public init(
        percent: Double? = nil,
        state: BatteryChargeState = .unavailable,
        batteryWatts: Double? = nil,
        adapterWatts: Double? = nil,
        adapterLimitWatts: Double? = nil,
        systemWatts: Double? = nil,
        voltageVolts: Double? = nil,
        amperageMilliamps: Double? = nil,
        minutesRemaining: Int? = nil,
        cycleCount: Int? = nil,
        healthPercent: Double? = nil
    ) {
        self.percent = percent
        self.state = state
        self.batteryWatts = batteryWatts
        self.adapterWatts = adapterWatts
        self.adapterLimitWatts = adapterLimitWatts
        self.systemWatts = systemWatts
        self.voltageVolts = voltageVolts
        self.amperageMilliamps = amperageMilliamps
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
    }

    public var isAvailable: Bool {
        state != .unavailable
    }

    public var percentLabel: String {
        guard let percent else { return "—" }
        return String(format: "%.0f%%", percent)
    }

    public var batteryWattsLabel: String {
        Self.formatSignedWatts(batteryWatts)
    }

    public var adapterLine: String {
        switch (adapterWatts, adapterLimitWatts) {
        case let (live?, limit?):
            return String(format: "%.0f W of %.0f W adapter", live, limit)
        case let (live?, nil):
            return String(format: "%.0f W adapter", live)
        case let (nil, limit?):
            return String(format: "%.0f W adapter", limit)
        default:
            return "No adapter"
        }
    }

    public var timeLabel: String? {
        guard let minutesRemaining, minutesRemaining > 0, minutesRemaining < 24 * 60 else {
            return nil
        }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        let clock: String
        if hours > 0 {
            clock = "\(hours)h \(minutes)m"
        } else {
            clock = "\(minutes)m"
        }
        switch state {
        case .charging:
            return "\(clock) to full"
        case .discharging:
            return "\(clock) remaining"
        default:
            return clock
        }
    }

    public var diagnosticLine: String {
        var parts = [state.label, percentLabel]
        if let batteryWatts {
            parts.append(String(format: "battery %.1f W", batteryWatts))
        }
        if let adapterWatts {
            parts.append(String(format: "adapter %.1f W", adapterWatts))
        }
        if let adapterLimitWatts {
            parts.append(String(format: "limit %.0f W", adapterLimitWatts))
        }
        if let systemWatts {
            parts.append(String(format: "system %.1f W", systemWatts))
        }
        if let cycleCount {
            parts.append("cycles \(cycleCount)")
        }
        return "Battery: " + parts.joined(separator: ", ")
    }

    public static func formatSignedWatts(_ watts: Double?) -> String {
        guard let watts else { return "—" }
        if watts > 0.4 {
            return String(format: "+%.0f W", watts)
        }
        if watts < -0.4 {
            return String(format: "−%.0f W", abs(watts))
        }
        return "0 W"
    }
}

enum BatteryMath {
    static func percent(current: Double, maximum: Double) -> Double? {
        guard maximum > 0, current >= 0 else { return nil }
        let value = maximum <= 100 ? current : (current / maximum) * 100
        return Swift.min(Swift.max(value, 0), 100)
    }

    static func healthPercent(maximum: Double, design: Double) -> Double? {
        guard design > 0, maximum > 0 else { return nil }
        return Swift.min(Swift.max((maximum / design) * 100, 0), 110)
    }

    static func wattsFromTelemetry(_ raw: Double) -> Double {
        if abs(raw) >= 200 {
            return raw / 1000
        }
        return raw
    }

    static func volts(from raw: Double) -> Double {
        raw > 50 ? raw / 1000 : raw
    }

    static func milliamps(from raw: Int64) -> Double {
        if raw >= -30_000 && raw <= 30_000 {
            return Double(raw)
        }
        return Double(Int16(bitPattern: UInt16(truncatingIfNeeded: raw)))
    }

    static func state(isCharging: Bool, isPluggedIn: Bool, percent: Double?) -> BatteryChargeState {
        if isCharging {
            return .charging
        }
        if isPluggedIn, let percent, percent >= 98.5 {
            return .full
        }
        if isPluggedIn {
            return .pluggedNotCharging
        }
        return .discharging
    }

    static func batteryWatts(
        isCharging: Bool,
        milliamps: Double?,
        volts: Double?,
        telemetryWatts: Double?
    ) -> Double? {
        if let telemetryWatts, abs(telemetryWatts) >= 0.3 {
            return telemetryWatts
        }
        guard let milliamps, let volts, volts > 0 else { return telemetryWatts }
        let magnitude = abs(milliamps) * volts / 1000
        guard magnitude >= 0.3 else { return 0 }
        return isCharging ? magnitude : -magnitude
    }

    static func sanitizedMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 24 * 60 else { return nil }
        return value
    }
}
