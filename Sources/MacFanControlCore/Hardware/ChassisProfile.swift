import Foundation

/// Rough chassis class so Quiet / Balanced / Performance can use sensible
/// temperature ramps on thin Air machines and thicker Pro machines alike.
public enum ChassisKind: String, Sendable, Equatable {
    case macBookAir
    case macBookPro
    case other

    public var shortLabel: String {
        switch self {
        case .macBookAir: return "MacBook Air"
        case .macBookPro: return "MacBook Pro"
        case .other: return "MacBook"
        }
    }

    public var tip: String {
        switch self {
        case .macBookAir:
            return "Air tip: Quiet stays soft for everyday work. Balanced is the usual sweet spot under load."
        case .macBookPro:
            return "Pro tip: Performance cools earlier so firmware can hold clocks. It does not raise TDP."
        case .other:
            return "Curves adapt to your fan range. Performance cools earlier; it does not overclock."
        }
    }
}

public struct ChassisProfile: Sendable, Equatable {
    public let kind: ChassisKind
    public let modelIdentifier: String
    public let fanCount: Int

    public init(kind: ChassisKind, modelIdentifier: String, fanCount: Int) {
        self.kind = kind
        self.modelIdentifier = modelIdentifier
        self.fanCount = fanCount
    }

    public var summaryLabel: String {
        let fans = fanCount == 1 ? "1 fan" : "\(fanCount) fans"
        return "\(kind.shortLabel) · \(fans)"
    }

    public static func detect(fanCount: Int) -> ChassisProfile {
        let identifier = modelIdentifier()
        let kind = classify(modelIdentifier: identifier, fanCount: fanCount)
        return ChassisProfile(kind: kind, modelIdentifier: identifier, fanCount: fanCount)
    }

    public func ramp(for preset: CurvePreset) -> (start: Double, end: Double) {
        switch (kind, preset) {
        case (.macBookAir, .quiet):
            return (74, 92)
        case (.macBookAir, .balanced):
            return (68, 86)
        case (.macBookAir, .performance):
            // Air stocks quiet and climbs fast — start earlier so clocks hold.
            return (60, 82)
        case (.macBookPro, .quiet):
            return (72, 90)
        case (.macBookPro, .balanced):
            return (68, 87)
        case (.macBookPro, .performance):
            return (65, 85)
        case (.other, .quiet):
            return (73, 91)
        case (.other, .balanced):
            return (68, 86)
        case (.other, .performance):
            return (65, 85)
        }
    }

    /// Soft ceiling so Quiet never commands absolute max on thin chassis.
    public func rpmCeilingFraction(for preset: CurvePreset) -> Double {
        switch (kind, preset) {
        case (.macBookAir, .quiet):
            return 0.82
        case (.macBookAir, .balanced):
            return 0.92
        case (.macBookPro, .quiet):
            return 0.88
        default:
            return 1.0
        }
    }

    private static func classify(modelIdentifier: String, fanCount: Int) -> ChassisKind {
        let id = modelIdentifier.lowercased()
        if id.contains("macbookair") || id.hasPrefix("macbookair") {
            return .macBookAir
        }
        if id.contains("macbookpro") {
            return .macBookPro
        }
        // Apple Silicon marketing identifiers are often Mac14,2 style.
        // Prefer fan count as a soft hint when the string is opaque.
        if fanCount <= 1, looksLikeAppleSiliconIdentifier(id) {
            return .macBookAir
        }
        if fanCount >= 2, looksLikeAppleSiliconIdentifier(id) {
            return .macBookPro
        }
        return .other
    }

    private static func looksLikeAppleSiliconIdentifier(_ id: String) -> Bool {
        // e.g. mac14,2 / mac16,12
        let compact = id.replacingOccurrences(of: " ", with: "")
        return compact.hasPrefix("mac") && compact.contains(",")
    }

    private static func modelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
