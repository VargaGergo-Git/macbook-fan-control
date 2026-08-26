import Foundation

enum PrivilegedSMC {
    static var canWriteDirectly: Bool {
        geteuid() == 0
    }

    static var helperAvailable: Bool {
        HelperLocator.path != nil
    }

    static var helperSearchSummary: String {
        HelperLocator.searchSummary
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
        guard let helperPath = HelperLocator.path else {
            throw PrivilegedError.helperMissing
        }

        let command = ([helperPath] + arguments)
            .map(shellEscape)
            .joined(separator: " ")

        try runAsAdmin(command: command)
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAsAdmin(command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let combined = message ?? "Helper exited with code \(process.terminationStatus)."
            if combined.localizedCaseInsensitiveContains("User canceled")
                || combined.contains("(-128)")
                || combined.localizedCaseInsensitiveContains("cancelled") {
                throw PrivilegedError.authorizationDenied
            }
            throw PrivilegedError.helperFailed(combined)
        }
    }
}

enum HelperLocator {
    static var path: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var searchSummary: String {
        let checked = candidatePaths
        if checked.isEmpty {
            return "No helper search paths."
        }
        return checked.map { path in
            let exists = FileManager.default.fileExists(atPath: path)
            let executable = FileManager.default.isExecutableFile(atPath: path)
            return "\(path) [exists=\(exists), exec=\(executable)]"
        }.joined(separator: "\n")
    }

    static var candidatePaths: [String] {
        var paths: [String] = []
        let helperName = "MacFanControlHelper"

        func appendUnique(_ path: String) {
            if !paths.contains(path) {
                paths.append(path)
            }
        }

        if let override = ProcessInfo.processInfo.environment["MACFANCONTROL_HELPER"] {
            appendUnique(override)
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        appendUnique(executable.deletingLastPathComponent().appendingPathComponent(helperName).path)

        if let bundleExecutable = Bundle.main.executableURL?.standardizedFileURL {
            appendUnique(bundleExecutable.deletingLastPathComponent().appendingPathComponent(helperName).path)
        }

        for path in buildDirectoryCandidates(near: executable.deletingLastPathComponent().path) {
            appendUnique(path)
        }
        for path in buildDirectoryCandidates(near: FileManager.default.currentDirectoryPath) {
            appendUnique(path)
        }

        return paths
    }

    private static func buildDirectoryCandidates(near basePath: String) -> [String] {
        var results: [String] = []
        var directory = URL(fileURLWithPath: basePath).standardizedFileURL

        for _ in 0..<6 {
            let buildRoot = directory.appendingPathComponent(".build")
            if FileManager.default.fileExists(atPath: buildRoot.path) {
                results.append(contentsOf: findHelperExecutables(in: buildRoot.path))
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }

        return results
    }

    private static func findHelperExecutables(in buildRoot: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: buildRoot) else {
            return []
        }

        var matches: [String] = []
        for case let relativePath as String in enumerator {
            guard relativePath.hasSuffix("MacFanControlHelper") else { continue }
            guard !relativePath.contains(".dSYM/") else { continue }

            let fullPath = (buildRoot as NSString).appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            matches.append(fullPath)
        }

        return matches.sorted { lhs, rhs in
            lhs.contains("/release/") && !rhs.contains("/release/")
        }
    }
}
