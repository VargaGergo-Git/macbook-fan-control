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
        let suffix = String(key.dropFirst())
        if suffix.contains("C") || suffix.hasPrefix("C") { return "CPU" }
        if suffix.contains("G") || suffix.hasPrefix("G") { return "GPU" }
        if suffix.contains("B") { return "Battery" }
        if suffix.contains("P") { return "Platform" }
        if suffix.contains("A") { return "Ambient" }
        return "Other"
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

    private static let knownTemperatureNames: [String: String] = [
        "TC0P": "CPU Proximity",
        "TC0D": "CPU Die",
        "TC0E": "CPU",
        "TC0F": "CPU",
        "TG0P": "GPU Proximity",
        "TG0D": "GPU Die",
        "TH0P": "Heatsink",
        "TM0P": "Memory Proximity",
        "TN0D": "Northbridge Die",
        "TB0T": "Battery",
        "Ta0P": "Ambient",
        "TW0P": "Airport",
        "Tp0P": "Platform Controller",
        "Tc0p": "CPU Package",
        "Tg0P": "GPU Package",
        "Th0P": "Heat Pipe"
    ]
}

enum SMCConstants {
    static let fanCountKey = "FNum"
    static let ftstKey = "Ftst"
    static let maxFanCount = 4
}
