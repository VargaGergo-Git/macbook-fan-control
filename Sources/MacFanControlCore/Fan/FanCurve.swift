import Foundation

public enum CurvePreset: String, Sendable, Equatable, CaseIterable {
    case quiet
    case balanced
    case performance

    public var title: String {
        switch self {
        case .quiet: return "Quiet"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }

    public var subtitle: String {
        switch self {
        case .quiet: return "Soft cabin"
        case .balanced: return "Daily load"
        case .performance: return "Hold clocks"
        }
    }
}

public enum ControlMode: String, Sendable, Equatable {
    case appleAuto
    case quietCurve
    case balancedCurve
    case performanceCurve
    case fixedRPM

    public var badgeLabel: String {
        switch self {
        case .appleAuto: return "Auto"
        case .quietCurve: return "Quiet"
        case .balancedCurve: return "Balanced"
        case .performanceCurve: return "Performance"
        case .fixedRPM: return "Manual"
        }
    }

    public var curvePreset: CurvePreset? {
        switch self {
        case .quietCurve: return .quiet
        case .balancedCurve: return .balanced
        case .performanceCurve: return .performance
        case .appleAuto, .fixedRPM: return nil
        }
    }

    public static func curve(_ preset: CurvePreset) -> ControlMode {
        switch preset {
        case .quiet: return .quietCurve
        case .balanced: return .balancedCurve
        case .performance: return .performanceCurve
        }
    }
}

/// Proactive cooling for Apple Silicon: spin earlier than macOS so firmware
/// can hold clocks. Does not raise TDP or overclock. Ramps adapt for Air vs Pro.
public enum FanCurve {
    public static func targetRPM(
        temperature: Double,
        minRPM: Double,
        maxRPM: Double,
        preset: CurvePreset,
        chassis: ChassisProfile
    ) -> Double {
        let ramp = chassis.ramp(for: preset)
        let low = min(minRPM, maxRPM)
        let absoluteHigh = max(minRPM, maxRPM)
        let high = low + (absoluteHigh - low) * chassis.rpmCeilingFraction(for: preset)
        if high <= low { return low }
        if temperature <= ramp.start { return low }
        if temperature >= ramp.end { return high }
        let span = ramp.end - ramp.start
        let t = (temperature - ramp.start) / span
        return low + (high - low) * t
    }

    /// Backwards-compatible Pro Performance ramp used by older call sites/tests.
    public static func targetRPM(temperature: Double, minRPM: Double, maxRPM: Double) -> Double {
        let chassis = ChassisProfile(kind: .macBookPro, modelIdentifier: "MacBookPro", fanCount: 2)
        return targetRPM(
            temperature: temperature,
            minRPM: minRPM,
            maxRPM: maxRPM,
            preset: .performance,
            chassis: chassis
        )
    }

    public static func hottestDieCelsius(in sensors: [TemperatureSensor]) -> Double? {
        let preferred = sensors.filter { $0.component == "CPU" || $0.component == "GPU" }
        if let hot = preferred.map(\.celsius).max() {
            return hot
        }
        // Air and some Intel machines expose fewer die keys — use any sensor.
        return sensors.map(\.celsius).max()
    }

    public static func statusMessage(
        preset: CurvePreset,
        chassis: ChassisProfile,
        temperature: Double?
    ) -> String {
        let ramp = chassis.ramp(for: preset)
        if let temperature {
            return String(
                format: "%@ on %@: %.0f °C die. Fans ramp %.0f→%.0f °C — cools earlier, does not raise TDP.",
                preset.title,
                chassis.kind.shortLabel,
                temperature,
                ramp.start,
                ramp.end
            )
        }
        return String(
            format: "%@ on %@: fans ramp %.0f→%.0f °C. Cools earlier; does not raise TDP.",
            preset.title,
            chassis.kind.shortLabel,
            ramp.start,
            ramp.end
        )
    }

    /// Sample the active chassis curve for preview charts (temp °C → RPM).
    public static func curveSamples(
        minRPM: Double,
        maxRPM: Double,
        preset: CurvePreset,
        chassis: ChassisProfile,
        fromTemperature: Double = 40,
        toTemperature: Double = 100,
        step: Double = 2
    ) -> [(temperature: Double, rpm: Double)] {
        let lo = min(fromTemperature, toTemperature)
        let hi = max(fromTemperature, toTemperature)
        let strideStep = max(step, 0.5)
        var points: [(temperature: Double, rpm: Double)] = []
        var temperature = lo
        while temperature <= hi + 0.001 {
            points.append(
                (
                    temperature,
                    targetRPM(
                        temperature: temperature,
                        minRPM: minRPM,
                        maxRPM: maxRPM,
                        preset: preset,
                        chassis: chassis
                    )
                )
            )
            temperature += strideStep
        }
        return points
    }
}

public enum TemperatureSummary {
    public static let preferredComponents = ["CPU", "GPU", "Battery", "Wi-Fi", "System", "Storage"]

    public static func hottestByComponent(_ sensors: [TemperatureSensor]) -> [TemperatureSensor] {
        let groups = Dictionary(grouping: sensors, by: \.component)
        let preferred = preferredComponents.compactMap { component in
            groups[component]?.max(by: { $0.celsius < $1.celsius })
        }
        if !preferred.isEmpty {
            return Array(preferred.prefix(4))
        }
        // Fallback: top unique components by temperature for unusual sensor maps.
        return sensors
            .sorted { $0.celsius > $1.celsius }
            .reduce(into: [TemperatureSensor]()) { result, sensor in
                guard result.count < 4 else { return }
                guard !result.contains(where: { $0.component == sensor.component }) else { return }
                result.append(sensor)
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
