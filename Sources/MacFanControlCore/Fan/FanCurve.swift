import Foundation

public enum ControlMode: String, Sendable, Equatable {
    case appleAuto
    case performanceCurve
    case fixedRPM

    public var badgeLabel: String {
        switch self {
        case .appleAuto: return "Auto"
        case .performanceCurve: return "Performance"
        case .fixedRPM: return "Manual"
        }
    }
}

/// Proactive cooling for Apple Silicon: spin earlier than macOS so firmware
/// can hold clocks. Does not raise TDP or overclock.
public enum FanCurve {
    public static let rampStartCelsius = 65.0
    public static let rampEndCelsius = 85.0

    public static func targetRPM(temperature: Double, minRPM: Double, maxRPM: Double) -> Double {
        let low = min(minRPM, maxRPM)
        let high = max(minRPM, maxRPM)
        if high <= low { return low }
        if temperature <= rampStartCelsius { return low }
        if temperature >= rampEndCelsius { return high }
        let span = rampEndCelsius - rampStartCelsius
        let t = (temperature - rampStartCelsius) / span
        return low + (high - low) * t
    }

    public static func hottestDieCelsius(in sensors: [TemperatureSensor]) -> Double? {
        sensors
            .filter { $0.component == "CPU" || $0.component == "GPU" }
            .map(\.celsius)
            .max()
    }
}

public enum TemperatureSummary {
    public static let preferredComponents = ["CPU", "GPU", "Battery", "Wi-Fi"]

    public static func hottestByComponent(_ sensors: [TemperatureSensor]) -> [TemperatureSensor] {
        let groups = Dictionary(grouping: sensors, by: \.component)
        return preferredComponents.compactMap { component in
            groups[component]?.max(by: { $0.celsius < $1.celsius })
        }
    }
}

public struct HistorySample: Sendable, Equatable {
    public let time: Date
    public let cpuCelsius: Double?
    public let gpuCelsius: Double?
    public let fanRPM: Double?
    public let pressure: ThermalPressure

    public init(
        time: Date,
        cpuCelsius: Double?,
        gpuCelsius: Double?,
        fanRPM: Double?,
        pressure: ThermalPressure
    ) {
        self.time = time
        self.cpuCelsius = cpuCelsius
        self.gpuCelsius = gpuCelsius
        self.fanRPM = fanRPM
        self.pressure = pressure
    }
}

enum HistoryBuffer {
    static let capacity = 480

    static func appending(_ samples: [HistorySample], _ sample: HistorySample) -> [HistorySample] {
        var next = samples
        next.append(sample)
        if next.count > capacity {
            next.removeFirst(next.count - capacity)
        }
        return next
    }
}
