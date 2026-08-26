import Foundation
import MacFanControlCore

enum HelperCommand {
    static func run() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard !args.isEmpty else {
            printUsage()
            exit(1)
        }

        do {
            let smc = SMCService()
            try smc.open()
            defer { smc.close() }

            switch args[0] {
            case "write-u8":
                guard args.count == 3, let value = UInt8(args[2]) else {
                    throw HelperError.invalidArguments
                }
                try smc.writeUInt8(args[1], value: value)

            case "write-float":
                guard args.count == 3, let value = Double(args[2]) else {
                    throw HelperError.invalidArguments
                }
                try smc.writeFloatRPM(args[1], value: value)

            case "unlock-manual":
                guard args.count == 3 else {
                    throw HelperError.invalidArguments
                }
                try FanWriteOperations.unlockManualControl(
                    smc: smc,
                    modeKey: args[1],
                    useFtst: args[2] == "1"
                )

            case "set-fan-manual-rpm":
                guard args.count == 5, let rpm = Double(args[3]) else {
                    throw HelperError.invalidArguments
                }
                try FanWriteOperations.setManualRPM(
                    smc: smc,
                    modeKey: args[1],
                    targetKey: args[2],
                    rpm: rpm,
                    useFtst: args[4] == "1"
                )

            case "set-fans-auto":
                guard args.count == 3 else {
                    throw HelperError.invalidArguments
                }
                let modeKeys = args[1].split(separator: ",").map(String.init)
                try FanWriteOperations.setAutomatic(
                    smc: smc,
                    modeKeys: modeKeys,
                    clearFtst: args[2] == "1"
                )

            default:
                throw HelperError.invalidArguments
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func printUsage() {
        fputs(
            """
            usage: MacFanControlHelper <command> [args]
              write-u8 <key> <value>
              write-float <key> <value>
              unlock-manual <modeKey> <useFtst:0|1>
              set-fan-manual-rpm <modeKey> <targetKey> <rpm> <useFtst:0|1>
              set-fans-auto <modeKey1,modeKey2,...> <clearFtst:0|1>

            """,
            stderr
        )
    }
}

enum HelperError: Error, LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Invalid helper arguments."
        }
    }
}

HelperCommand.run()
