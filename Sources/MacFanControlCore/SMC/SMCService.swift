import Foundation
import IOKit

struct SMCKeyData {
    let key: String
    let data: Data
    let dataSize: UInt32
    let dataType: UInt32
}

enum SMCError: Error, LocalizedError {
    case connectionFailed(kern_return_t)
    case structLayoutInvalid(Int)
    case keyNotFound(String)
    case readFailed(String, smcResult: UInt8)
    case writeFailed(String, smcResult: UInt8)
    case notPrivileged
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let code):
            return "Unable to connect to AppleSMC (IOKit error 0x\(String(code, radix: 16)))."
        case .structLayoutInvalid(let size):
            return "Internal SMC struct layout invalid (\(size) bytes, expected 80)."
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .readFailed(let key, let smcResult):
            return "Failed to read SMC key \(key) (SMC status 0x\(String(smcResult, radix: 16)))."
        case .writeFailed(let key, let smcResult):
            return "Failed to write SMC key \(key) (SMC status 0x\(String(smcResult, radix: 16)))."
        case .notPrivileged:
            return "Administrator privileges are required for this SMC operation."
        case .unsupportedPlatform:
            return "SMC is only available on macOS."
        }
    }
}

#if os(macOS)
private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private enum SMCCommand: UInt8 {
    case readKey = 5
    case writeKey = 6
    case getKeyInfo = 9
}

private enum SMCResult: UInt8 {
    case success = 0
    case keyNotFound = 132
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersionStruct()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
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

private let kSMCHandleYPCEvent: UInt32 = 2
#endif

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
        let structSize = MemoryLayout<SMCParamStruct>.stride
        guard structSize == 80 else {
            throw SMCError.structLayoutInvalid(structSize)
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            throw SMCError.connectionFailed(kIOReturnNotFound)
        }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            throw SMCError.connectionFailed(result)
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
        let encodedKey = SMCKeyCodec.encodeKey(key)

        var infoInput = SMCParamStruct()
        infoInput.key = encodedKey
        infoInput.data8 = SMCCommand.getKeyInfo.rawValue
        let infoOutput = try call(infoInput, isWrite: false, keyLabel: key)

        var readInput = SMCParamStruct()
        readInput.key = encodedKey
        readInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        readInput.data8 = SMCCommand.readKey.rawValue
        let readOutput = try call(readInput, isWrite: false, keyLabel: key)

        let size = Int(infoOutput.keyInfo.dataSize)
        let data = bytesToData(readOutput.bytes, count: size)

        return SMCKeyData(
            key: key,
            data: data,
            dataSize: infoOutput.keyInfo.dataSize,
            dataType: infoOutput.keyInfo.dataType
        )
        #endif
    }

    func writeKey(_ key: String, data: Data, dataSize: UInt32? = nil) throws {
        #if !os(macOS)
        throw SMCError.unsupportedPlatform
        #else
        let encodedKey = SMCKeyCodec.encodeKey(key)
        let size = dataSize ?? UInt32(min(data.count, 32))

        var input = SMCParamStruct()
        input.key = encodedKey
        input.keyInfo.dataSize = size
        input.bytes = dataToBytes(data, count: Int(size))
        input.data8 = SMCCommand.writeKey.rawValue

        _ = try call(input, isWrite: true, keyLabel: key)
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
        try writeKey(key, data: SMCKeyCodec.encodeUI8(value), dataSize: 1)
    }

    func writeFloatRPM(_ key: String, value: Double) throws {
        try writeKey(key, data: SMCKeyCodec.encodeFloat(value), dataSize: 4)
    }

    func enumerateTemperatureKeys(limit: Int = 64) -> [TemperatureSensor] {
        var sensors: [TemperatureSensor] = []
        var seenKeys = Set<String>()

        func appendSensor(key: String) {
            guard !seenKeys.contains(key), sensors.count < limit else { return }
            guard let keyData = try? readKey(key) else { return }
            guard let celsius = SMCKeyCodec.decodeTemperature(
                key: key,
                bytes: keyData.data,
                size: keyData.dataSize
            ), celsius > -50, celsius < 150 else {
                return
            }

            seenKeys.insert(key)
            sensors.append(
                TemperatureSensor(
                    id: key,
                    name: SMCKeyCodec.friendlySensorName(for: key),
                    component: SMCKeyCodec.componentName(for: key),
                    celsius: celsius
                )
            )
        }

        for key in SMCKeyCodec.knownTemperatureKeys {
            appendSensor(key: key)
        }

        for index in 0..<256 where sensors.count < limit {
            appendSensor(key: String(format: "T%03X", index))
        }

        return sensors.sorted { $0.celsius > $1.celsius }
    }

    #if os(macOS)
    private func call(_ input: SMCParamStruct, isWrite: Bool, keyLabel: String) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let ioResult = IOConnectCallStructMethod(
            connection,
            kSMCHandleYPCEvent,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )

        if ioResult == kIOReturnNotPrivileged {
            throw SMCError.notPrivileged
        }

        guard ioResult == KERN_SUCCESS else {
            throw isWrite
                ? SMCError.writeFailed(keyLabel, smcResult: output.result)
                : SMCError.readFailed(keyLabel, smcResult: output.result)
        }

        if output.result == SMCResult.keyNotFound.rawValue {
            throw SMCError.keyNotFound(keyLabel)
        }

        guard output.result == SMCResult.success.rawValue else {
            throw isWrite
                ? SMCError.writeFailed(keyLabel, smcResult: output.result)
                : SMCError.readFailed(keyLabel, smcResult: output.result)
        }

        return output
    }

    private func bytesToData(_ bytes: SMCBytes, count: Int) -> Data {
        withUnsafeBytes(of: bytes) { raw in
            Data(raw.prefix(max(0, min(count, 32))))
        }
    }

    private func dataToBytes(_ data: Data, count: Int) -> SMCBytes {
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )

        data.withUnsafeBytes { raw in
            withUnsafeMutableBytes(of: &bytes) { dest in
                guard let src = raw.baseAddress, let dst = dest.baseAddress else { return }
                memcpy(dst, src, min(raw.count, count, 32))
            }
        }

        return bytes
    }
    #endif
}
