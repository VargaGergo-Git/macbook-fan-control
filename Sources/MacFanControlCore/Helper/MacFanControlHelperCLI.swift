import Foundation

public enum MacFanControlHelperCLI {
    public enum ExitCode: Int32 {
        case success = 0
        case failure = 1
    }

    @discardableResult
    public static func run(arguments: [String]) -> ExitCode {
        guard let command = arguments.first else {
            printUsage()
            return .failure
        }

        if command == "daemon" {
            return runDaemon(arguments: Array(arguments.dropFirst()))
        }

        do {
            let smc = SMCService()
            try smc.open()
            defer { smc.close() }
            try execute(arguments: arguments, smc: smc)
            return .success
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return .failure
        }
    }

    static func execute(arguments: [String], smc: SMCService) throws {
        guard let command = arguments.first else {
            throw HelperCLIError.invalidArguments
        }

        switch command {
        case "write-u8":
            guard arguments.count == 3, let value = UInt8(arguments[2]) else {
                throw HelperCLIError.invalidArguments
            }
            try smc.writeUInt8(arguments[1], value: value)

        case "write-float":
            guard arguments.count == 3, let value = Double(arguments[2]) else {
                throw HelperCLIError.invalidArguments
            }
            try smc.writeFloatRPM(arguments[1], value: value)

        case "unlock-manual":
            guard arguments.count == 3 else {
                throw HelperCLIError.invalidArguments
            }
            try FanWriteOperations.unlockManualControl(
                smc: smc,
                modeKey: arguments[1],
                useFtst: arguments[2] == "1"
            )

        case "set-fan-manual-rpm":
            guard arguments.count == 5, let rpm = Double(arguments[3]) else {
                throw HelperCLIError.invalidArguments
            }
            try FanWriteOperations.setManualRPM(
                smc: smc,
                modeKey: arguments[1],
                targetKey: arguments[2],
                rpm: rpm,
                useFtst: arguments[4] == "1"
            )

        case "set-fans-auto":
            guard arguments.count == 3 else {
                throw HelperCLIError.invalidArguments
            }
            let modeKeys = arguments[1].split(separator: ",").map(String.init)
            try FanWriteOperations.setAutomatic(
                smc: smc,
                modeKeys: modeKeys,
                clearFtst: arguments[2] == "1"
            )

        default:
            throw HelperCLIError.invalidArguments
        }
    }

    public static func printUsage() {
        fputs(
            """
            usage: MacFanControlHelper <command> [args]
              daemon <socketPath> <uid>
              write-u8 <key> <value>
              write-float <key> <value>
              unlock-manual <modeKey> <useFtst:0|1>
              set-fan-manual-rpm <modeKey> <targetKey> <rpm> <useFtst:0|1>
              set-fans-auto <modeKey1,modeKey2,...> <clearFtst:0|1>

            """,
            stderr
        )
    }

    private static func runDaemon(arguments: [String]) -> ExitCode {
        guard let socketPath = arguments.first else {
            printUsage()
            return .failure
        }

        let uid: uid_t
        if arguments.count >= 2, let parsed = UInt32(arguments[1]) {
            uid = uid_t(parsed)
        } else {
            uid = getuid()
        }

        do {
            try PrivilegedWriteDaemon.run(socketPath: socketPath, allowedUID: uid)
            return .success
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            return .failure
        }
    }
}

enum HelperCLIError: Error, LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Invalid helper arguments."
        }
    }
}
