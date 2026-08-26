import Foundation

public enum FanMode: Int, Sendable {
    case automatic = 0
    case manual = 1
    case system = 3
}

public struct Fan: Identifiable, Sendable {
    public let id: Int
    public let modeKey: String
    public var actualRPM: Double
    public var targetRPM: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var mode: FanMode

    public init(
        id: Int,
        modeKey: String,
        actualRPM: Double,
        targetRPM: Double,
        minRPM: Double,
        maxRPM: Double,
        mode: FanMode
    ) {
        self.id = id
        self.modeKey = modeKey
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.mode = mode
    }
}

public struct TemperatureSensor: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let component: String
    public var celsius: Double

    public init(id: String, name: String, component: String, celsius: Double) {
        self.id = id
        self.name = name
        self.component = component
        self.celsius = celsius
    }
}

public struct HardwareProfile: Sendable {
    public let fanCount: Int
    public let fanModeKeys: [String]
    public let hasFtstKey: Bool
    public let chipDescription: String
    public let macOSVersion: String

    public init(
        fanCount: Int,
        fanModeKeys: [String],
        hasFtstKey: Bool,
        chipDescription: String,
        macOSVersion: String
    ) {
        self.fanCount = fanCount
        self.fanModeKeys = fanModeKeys
        self.hasFtstKey = hasFtstKey
        self.chipDescription = chipDescription
        self.macOSVersion = macOSVersion
    }
}

public struct DiagnosticReport: Sendable {
    public let profile: HardwareProfile
    public let fans: [Fan]
    public let sensorCount: Int
    public let readOnly: Bool
    public let notes: [String]

    public var text: String {
        var lines: [String] = [
            "MacFanControl Diagnostic Report",
            "===============================",
            "Chip: \(profile.chipDescription)",
            "macOS: \(profile.macOSVersion)",
            "Fan count: \(profile.fanCount)",
            "Ftst key available: \(profile.hasFtstKey)",
            "Read-only mode: \(readOnly)",
            "Temperature sensors: \(sensorCount)",
            "Helper available: \(PrivilegedSMC.helperAvailable)",
            "Running as root: \(PrivilegedSMC.canWriteDirectly)",
            "Fan helper running: \(PrivilegedSMC.sessionAlive)",
            ""
        ]

        if !PrivilegedSMC.helperAvailable {
            lines.append("Helper search paths:")
            for path in HelperLocator.candidatePaths {
                lines.append("  - \(path)")
            }
            lines.append("")
        }

        for fan in fans {
            lines.append("Fan \(fan.id):")
            lines.append("  Mode key: \(fan.modeKey)")
            lines.append("  Actual RPM: \(Int(fan.actualRPM))")
            lines.append("  Target RPM: \(Int(fan.targetRPM))")
            lines.append("  Range: \(Int(fan.minRPM))–\(Int(fan.maxRPM))")
            lines.append("  Mode: \(fan.mode.rawValue)")
            lines.append("")
        }

        if !notes.isEmpty {
            lines.append("Notes:")
            for note in notes {
                lines.append("- \(note)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
