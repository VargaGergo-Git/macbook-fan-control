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
        return Double(bitPattern: bits)
    }

    public static func encodeFloat(_ value: Double) -> Data {
        var bits = value.bitPattern
        return withUnsafeBytes(of: &bits) { Data($0) }
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

    static func decodeTemperature(key: String, bytes: Data, size: UInt32) -> Double? {
        switch size {
        case 2:
            if key.hasPrefix("T") {
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
        key
    }
}

enum SMCConstants {
    static let fanCountKey = "FNum"
    static let ftstKey = "Ftst"
    static let maxFanCount = 4
}
