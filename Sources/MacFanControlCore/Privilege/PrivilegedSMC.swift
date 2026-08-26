import Foundation

#if canImport(AppKit)
import AppKit
#endif

enum PrivilegedSMC {
    static var canWriteDirectly: Bool {
        geteuid() == 0
    }

    static var helperAvailable: Bool {
        FileManager.default.fileExists(atPath: HelperLocator.path)
    }

    static func writeUInt8(_ key: String, value: UInt8, using smc: SMCService) throws {
        if canWriteDirectly {
            try smc.writeUInt8(key, value: value)
            return
        }
        try runHelper(arguments: ["write-u8", key, String(value)])
    }

    static func writeFloatRPM(_ key: String, value: Double, using smc: SMCService) throws {
        if canWriteDirectly {
            try smc.writeFloatRPM(key, value: value)
            return
        }
        try runHelper(arguments: ["write-float", key, String(value)])
    }

    static func setManualRPM(
        modeKey: String,
        targetKey: String,
        rpm: Double,
        useFtst: Bool,
        using smc: SMCService
    ) throws {
        if canWriteDirectly {
            try FanWriteOperations.setManualRPM(
                smc: smc,
                modeKey: modeKey,
                targetKey: targetKey,
                rpm: rpm,
                useFtst: useFtst
            )
            return
        }
        try runHelper(arguments: [
            "set-fan-manual-rpm",
            modeKey,
            targetKey,
            String(rpm),
            useFtst ? "1" : "0"
        ])
    }

    static func setAutomatic(modeKeys: [String], clearFtst: Bool, using smc: SMCService) throws {
        if canWriteDirectly {
            try FanWriteOperations.setAutomatic(
                smc: smc,
                modeKeys: modeKeys,
                clearFtst: clearFtst
            )
            return
        }
        try runHelper(arguments: [
            "set-fans-auto",
            modeKeys.joined(separator: ","),
            clearFtst ? "1" : "0"
        ])
    }

    static func unlockManualControl(modeKey: String, useFtst: Bool, using smc: SMCService) throws {
        if canWriteDirectly {
            try FanWriteOperations.unlockManualControl(
                smc: smc,
                modeKey: modeKey,
                useFtst: useFtst
            )
            return
        }
        try runHelper(arguments: [
            "unlock-manual",
            modeKey,
            useFtst ? "1" : "0"
        ])
    }

    private static func runHelper(arguments: [String]) throws {
        guard helperAvailable else {
            throw PrivilegedError.helperMissing
        }

        let command = ([HelperLocator.path] + arguments)
            .map(shellEscape)
            .joined(separator: " ")

        try runAsAdmin(command: command)
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAsAdmin(command: String) throws {
        #if canImport(AppKit)
        let scriptSource = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        _ = script?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Administrator authorization failed."
            if message.localizedCaseInsensitiveContains("User canceled") {
                throw PrivilegedError.authorizationDenied
            }
            throw PrivilegedError.helperFailed(message)
        }
        #else
        throw PrivilegedError.helperMissing
        #endif
    }
}

enum HelperLocator {
    static var path: String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        return executable
            .deletingLastPathComponent()
            .appendingPathComponent("MacFanControlHelper")
            .path
    }
}
