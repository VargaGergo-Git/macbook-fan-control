import Foundation
import IOKit

struct SMCKeyData {
    let key: String
    let data: Data
    let dataSize: UInt32
}

enum SMCError: Error, LocalizedError {
    case connectionFailed
    case keyNotFound(String)
    case readFailed(String)
    case writeFailed(String, status: UInt8)
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Unable to connect to AppleSMC."
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .readFailed(let key):
            return "Failed to read SMC key: \(key)"
        case .writeFailed(let key, let status):
            return "Failed to write SMC key \(key) (status 0x\(String(status, radix: 16)))"
        case .unsupportedPlatform:
            return "SMC is only available on macOS."
        }
    }
}

final class SMCService {
    private var connection: io_connect_t = 0
    private(set) var isConnected = false

    deinit {
        close()
    }

    func open() throws {
        #if !os(macOS)
        throw SMCError.unsupportedPlatform
        #else
        let matching = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw SMCError.connectionFailed
        }
        defer { IOObjectRelease(iterator) }

        let device = IOIteratorNext(iterator)
        guard device != 0 else {
            throw SMCError.connectionFailed
        }
        defer { IOObjectRelease(device) }

        let result = IOServiceOpen(device, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            throw SMCError.connectionFailed
        }
        isConnected = true
        #endif
    }

    func close() {
        #if os(macOS)
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        #endif
        isConnected = false
    }

    func readKey(_ key: String) throws -> SMCKeyData {
        #if !os(macOS)
        throw SMCError.unsupportedPlatform
        #else
        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = SMCKeyCodec.encodeKey(key)
        input.data8 = SMCCommand.kernelIndex.rawValue
        input.data32 = UInt32(SMCCommand.readKeyInfo.rawValue)

        try call(&input, &output)

        input.key = SMCKeyCodec.encodeKey(key)
        input.data8 = SMCCommand.kernelIndex.rawValue
        input.data32 = UInt32(SMCCommand.readBytes.rawValue)
        input.dataSize = output.dataSize
        input.dataType = output.dataType

        try call(&input, &output)

        let size = Int(output.dataSize)
        let data = withUnsafeBytes(of: output.bytes) { raw in
            Data(raw.prefix(size))
        }

        return SMCKeyData(key: key, data: data, dataSize: output.dataSize)
        #endif
    }

    func writeKey(_ key: String, data: Data, dataType: UInt32 = SMCDataType.flt.rawValue) throws {
        #if !os(macOS)
        throw SMCError.unsupportedPlatform
        #else
        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = SMCKeyCodec.encodeKey(key)
        input.data8 = SMCCommand.kernelIndex.rawValue
        input.data32 = UInt32(SMCCommand.writeKeyInfo.rawValue)

        try call(&input, &output, isWrite: true)

        input.key = SMCKeyCodec.encodeKey(key)
        input.data8 = SMCCommand.kernelIndex.rawValue
        input.data32 = UInt32(SMCCommand.writeBytes.rawValue)
        input.dataSize = UInt32(min(data.count, 32))
        input.dataType = dataType

        data.withUnsafeBytes { raw in
            withUnsafeMutableBytes(of: &input.bytes) { dest in
                guard let src = raw.baseAddress, let dst = dest.baseAddress else { return }
                memcpy(dst, src, min(raw.count, 32))
            }
        }

        try call(&input, &output, isWrite: true)
        #endif
    }

    func keyExists(_ key: String) -> Bool {
        (try? readKey(key)) != nil
    }

    func readUInt8(_ key: String) throws -> UInt8 {
        SMCKeyCodec.decodeUI8(from: try readKey(key).data)
    }

    func readFloatRPM(_ key: String) throws -> Double {
        SMCKeyCodec.decodeFloat(from: try readKey(key).data)
    }

    func writeUInt8(_ key: String, value: UInt8) throws {
        try writeKey(key, data: SMCKeyCodec.encodeUI8(value), dataType: SMCDataType.ui8.rawValue)
    }

    func writeFloatRPM(_ key: String, value: Double) throws {
        try writeKey(key, data: SMCKeyCodec.encodeFloat(value), dataType: SMCDataType.flt.rawValue)
    }

    func enumerateTemperatureKeys(limit: Int = 64) -> [TemperatureSensor] {
        var sensors: [TemperatureSensor] = []

        for index in 0..<256 where sensors.count < limit {
            let key = String(format: "T%03X", index)
            guard let keyData = try? readKey(key) else { continue }
            guard let celsius = SMCKeyCodec.decodeTemperature(
                key: key,
                bytes: keyData.data,
                size: keyData.dataSize
            ), celsius > -50, celsius < 150 else {
                continue
            }

            sensors.append(
                TemperatureSensor(
                    id: key,
                    name: SMCKeyCodec.friendlySensorName(for: key),
                    component: SMCKeyCodec.componentName(for: key),
                    celsius: celsius
                )
            )
        }

        return sensors.sorted { $0.celsius > $1.celsius }
    }

    #if os(macOS)
    private func call(_ input: inout SMCParamStruct, _ output: inout SMCParamStruct, isWrite: Bool = false) throws {
        var size = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(kSMCHandleYPCEvent),
            &input,
            size,
            &output,
            &size
        )

        let keyLabel = fourCharacterString(from: input.key)

        guard result == KERN_SUCCESS else {
            throw isWrite
                ? SMCError.writeFailed(keyLabel, status: output.result)
                : SMCError.readFailed(keyLabel)
        }

        if output.result != 0 {
            throw isWrite
                ? SMCError.writeFailed(keyLabel, status: output.result)
                : SMCError.readFailed(keyLabel)
        }
    }

    private func fourCharacterString(from key: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((key >> 24) & 0xFF),
            UInt8((key >> 16) & 0xFF),
            UInt8((key >> 8) & 0xFF),
            UInt8(key & 0xFF)
        ]
        return String(bytes: chars, encoding: .ascii) ?? "????"
    }
    #endif
}

#if os(macOS)
private let kSMCHandleYPCEvent: UInt32 = 2

private enum SMCCommand: UInt8 {
    case kernelIndex = 0x00
    case readKeyInfo = 0x09
    case readBytes = 0x10
    case writeKeyInfo = 0x11
    case writeBytes = 0x12
}

private enum SMCDataType: UInt32 {
    case ui8 = 0x75693820  // "ui8 "
    case flt = 0x666C7420  // "flt "
    case fpe2 = 0x66706532 // "fpe2"
    case sp78 = 0x73703738 // "sp78"
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersionStruct()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    var dataSize: UInt32 {
        get { keyInfo.dataSize }
        set { keyInfo.dataSize = newValue }
    }

    var dataType: UInt32 {
        get { keyInfo.dataType }
        set { keyInfo.dataType = newValue }
    }
}

private struct SMCVersionStruct {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}
#endif
