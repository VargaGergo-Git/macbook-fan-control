import Foundation

public enum SMCKeyCodec {
    public static func encodeKey(_ key: String) -> UInt32 {
        precondition(key.count == 4, "SMC keys must be exactly 4 characters")
        var result: UInt32 = 0
        for char in key.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    static func decodeKey(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    static func fourCC(_ value: String) -> UInt32 {
        encodeKey(value.padding(toLength: 4, withPad: " ", startingAt: 0))
    }

    static func fanKey(prefix: String, index: Int) -> String {
        String(format: "\(prefix)%d", index)
    }

    public static func modeKeyCandidates(for index: Int) -> [String] {
        [
            fanKey(prefix: "F", index: index) + "Md",
            fanKey(prefix: "F", index: index) + "md"
        ]
    }

    public static func decodeFloat(from bytes: Data) -> Double {
        guard bytes.count >= 4 else { return 0 }
        let bits = bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
        return Double(Float(bitPattern: bits))
    }

    public static func encodeFloat(_ value: Double) -> Data {
        var floatValue = Float(value)
        return withUnsafeBytes(of: &floatValue) { Data($0) }
    }

    public static func decodeFPE2(from bytes: Data) -> Double {
        guard bytes.count >= 2 else { return 0 }
        let combined = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        let integer = combined >> 2
        let fraction = combined & 0x03
        return Double(integer) + Double(fraction) / 4.0
    }

    public static func encodeFPE2(_ value: Double) -> Data {
        let clamped = max(0, value)
        let integer = UInt16(clamped)
        let fraction = UInt16((clamped - Double(integer)) * 4.0) & 0x03
        let combined = (integer << 2) | fraction
        return Data([UInt8(combined >> 8), UInt8(combined & 0xFF)])
    }

    public static func decodeUI8(from bytes: Data) -> UInt8 {
        bytes.first ?? 0
    }

    public static func encodeUI8(_ value: UInt8) -> Data {
        Data([value])
    }

    static func decodeSP78(from bytes: Data) -> Double {
        guard let first = bytes.first else { return 0 }
        let sign: Double = (first & 0x80) != 0 ? -1 : 1
        let integer = Double(first & 0x7F)
        let fraction = bytes.count > 1 ? Double(bytes[1]) / 256.0 : 0
        return sign * (integer + fraction)
    }

    static func decodeTemperature(key: String, bytes: Data, size: UInt32, dataType: UInt32) -> Double? {
        switch dataType {
        case fourCC("sp78"), fourCC("sp87"), fourCC("sp96"):
            return decodeSP78(from: bytes)
        case fourCC("fpe2"):
            return decodeFPE2(from: bytes)
        case fourCC("flt "):
            return decodeFloat(from: bytes)
        case fourCC("ui16"):
            guard bytes.count >= 2 else { return nil }
            let raw = bytes.withUnsafeBytes { $0.load(as: UInt16.self) }
            return Double(raw) / 256.0
        default:
            break
        }

        switch size {
        case 2:
            if key.first == "T" || key.first == "t" {
                return decodeSP78(from: bytes)
            }
            return decodeFPE2(from: bytes)
        case 4:
            return decodeFloat(from: bytes)
        default:
            return nil
        }
    }

    public static func componentName(for key: String) -> String {
        if let mapped = knownComponentNames[key] {
            return mapped
        }

        let lower = key.lowercased()
        if lower == "th0b" { return "Battery" }
        if lower.hasPrefix("tc") || lower.hasPrefix("tp0c") || lower.hasPrefix("tp1c") { return "CPU" }
        if lower.hasPrefix("tg") { return "GPU" }
        if lower.hasPrefix("tb") { return "Battery" }
        if lower.hasPrefix("tw") { return "Wi-Fi" }
        if lower.hasPrefix("ta") || lower.hasPrefix("dta") { return "Ambient" }
        if lower.hasPrefix("tm") { return "Memory" }
        if lower.hasPrefix("tn") || lower.hasPrefix("tp") { return "System" }
        if lower.hasPrefix("th") { return "Heatsink" }
        if lower.hasPrefix("ts") { return "Storage" }
        if lower.hasPrefix("ac") { return "Power" }
        return "Other"
    }

    public static func componentSortOrder(_ component: String) -> Int {
        switch component {
        case "CPU": return 0
        case "GPU": return 1
        case "System": return 2
        case "Heatsink": return 3
        case "Memory": return 4
        case "Battery": return 5
        case "Wi-Fi": return 6
        case "Storage": return 7
        case "Ambient": return 8
        case "Power": return 9
        default: return 10
        }
    }

    static func friendlySensorName(for key: String) -> String {
        if let name = knownTemperatureNames[key] {
            return name
        }
        return key
    }

    /// Common SMC temperature keys across Intel and Apple Silicon MacBooks.
    static let knownTemperatureKeys: [String] = [
        // CPU
        "TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TC0c", "TC1c", "TC2c", "TC3c", "TC4c",
        "TCFC", "TCGC", "TCSc", "TCXC", "TCXc",
        "Tc0a", "Tc0b", "Tc0c", "Tc0d", "Tc0e", "Tc0f", "Tc0p",
        // GPU
        "TG0P", "TG0D", "TG0H", "TG0c", "TG1c", "TG2c",
        "Tg05", "Tg0D", "Tg0L", "Tg0P", "Tg0T", "Tg0d", "Tg0p",
        // Heatsink / logic board
        "TH0P", "TH0B", "TH0F", "THPS",
        "Th0H", "Th0L", "Th0P", "Th0R", "Th0a", "Th0b", "Th0c", "Th0x",
        // Memory
        "TM0P", "TM0S", "TM0b", "TMXP", "TMPS", "TMBS",
        "Tm0P", "Tm0p",
        // Northbridge / platform
        "TN0D", "TN0P", "TN0S",
        "Tp0P", "Tp0C", "Tp1C", "Tp09", "Tp0T", "Tp0t",
        // Battery
        "TB0T", "TB1T", "TB2T", "TBXT",
        // Ambient / wireless / SSD
        "Ta0P", "Ta0p", "TaLP",
        "TW0P", "TW0T",
        "Ts0P", "Ts0S",
        "AC0T", "AC1T",
        "dTaP", "dTa2",
        // Power / VRM
        "Th1H", "Th2H", "Th3H"
    ]

    private static let knownComponentNames: [String: String] = [
        "TH0B": "Battery",
        "TW0P": "Wi-Fi",
        "TW0T": "Wi-Fi"
    ]

    private static let knownTemperatureNames: [String: String] = [
        "TC0P": "CPU Proximity",
        "TC0D": "CPU Die",
        "TC0E": "CPU",
        "TC0F": "CPU",
        "TC0H": "CPU Heatsink",
        "TC0c": "CPU Core 1",
        "TC1c": "CPU Core 2",
        "TC2c": "CPU Core 3",
        "TC3c": "CPU Core 4",
        "TC4c": "CPU Core 5",
        "TCFC": "CPU PECI",
        "TCGC": "CPU Graphics",
        "TCXC": "CPU Exhaust",
        "TCXc": "CPU Exhaust",
        "Tc0a": "CPU",
        "Tc0b": "CPU",
        "Tc0c": "CPU",
        "Tc0d": "CPU Die",
        "Tc0e": "CPU",
        "Tc0f": "CPU",
        "Tc0p": "CPU Package",
        "TG0P": "GPU Proximity",
        "TG0D": "GPU Die",
        "TG0H": "GPU Heatsink",
        "TG0c": "GPU Core",
        "Tg05": "GPU",
        "Tg0D": "GPU Die",
        "Tg0L": "GPU",
        "Tg0P": "GPU Package",
        "Tg0T": "GPU",
        "Tg0d": "GPU Die",
        "Tg0p": "GPU Proximity",
        "TH0P": "Heatsink",
        "TH0B": "Battery",
        "TH0F": "Heatsink",
        "Th0H": "Heat Pipe",
        "Th0L": "Heat Pipe",
        "Th0P": "Heat Pipe",
        "Th0R": "Heat Pipe",
        "Th0a": "Heatsink",
        "Th0b": "Heatsink",
        "Th0c": "Heatsink",
        "TM0P": "Memory Proximity",
        "TM0S": "Memory",
        "Tm0P": "Memory",
        "Tm0p": "Memory",
        "TN0D": "Northbridge Die",
        "TN0P": "Platform",
        "Tp0P": "System",
        "Tp0C": "CPU",
        "Tp1C": "CPU",
        "Tp09": "System",
        "Tp0T": "System",
        "Tp0t": "System",
        "TB0T": "Battery",
        "TB1T": "Battery",
        "TB2T": "Battery",
        "TBXT": "Battery",
        "Ta0P": "Ambient",
        "Ta0p": "Ambient",
        "TW0P": "Wi-Fi",
        "TW0T": "Wi-Fi",
        "Ts0P": "Storage",
        "Ts0S": "Storage",
        "AC0T": "Power",
        "AC1T": "Power"
    ]
}

enum SMCConstants {
    static let fanCountKey = "FNum"
    static let ftstKey = "Ftst"
    static let maxFanCount = 4
}
