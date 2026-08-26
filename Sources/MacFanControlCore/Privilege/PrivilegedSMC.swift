import Foundation
import Darwin

enum PrivilegedSMC {
    private static let lock = NSLock()

    static var canWriteDirectly: Bool {
        geteuid() == 0
    }

    static var helperAvailable: Bool {
        HelperLocator.sourcePath != nil
    }

    static var sessionAlive: Bool {
        canWriteDirectly || PrivilegedWriteDaemon.ping(socketPath: socketPath)
    }

    static var helperSearchSummary: String {
        HelperLocator.searchSummary
    }

    private static var socketPath: String {
        PrivilegedWriteDaemon.socketPath(for: getuid())
    }

    /// Installs a LaunchDaemon helper. This is the only path that shows the
    /// macOS administrator dialog. Slider writes must never call this.
    static func ensureSession() throws {
        lock.lock()
        defer { lock.unlock() }

        if canWriteDirectly { return }
        if PrivilegedWriteDaemon.ping(socketPath: socketPath) { return }

        guard let helperPath = HelperLocator.sourcePath else {
            throw PrivilegedError.helperMissing
        }

        let uid = getuid()
        let sock = socketPath
        let logPath = PrivilegedWriteDaemon.logPath(for: uid)
        let script = installScript(
            helperPath: helperPath,
            socketPath: sock,
            uid: uid,
            logPath: logPath
        )

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macfancontrol-install-\(uid).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )

        try runAsAdmin(command: "/bin/bash \(shellEscape(scriptURL.path))")

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if PrivilegedWriteDaemon.ping(socketPath: sock) {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let logTail = ((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "")
            .split(separator: "\n")
            .suffix(12)
            .joined(separator: "\n")
        throw PrivilegedError.helperFailed(
            logTail.isEmpty
                ? "Could not start the authorized fan helper. Try Allow fan control again."
                : "Could not start the authorized fan helper:\n\(logTail)"
        )
    }

    static func writeUInt8(_ key: String, value: UInt8, using smc: SMCService? = nil) throws {
        if canWriteDirectly {
            guard let smc else { throw SMCError.notPrivileged }
            try smc.writeUInt8(key, value: value)
            return
        }
        try runHelper(arguments: ["write-u8", key, String(value)])
    }

    static func writeFloatRPM(_ key: String, value: Double, using smc: SMCService? = nil) throws {
        if canWriteDirectly {
            guard let smc else { throw SMCError.notPrivileged }
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
        using smc: SMCService? = nil
    ) throws {
        if canWriteDirectly {
            guard let smc else { throw SMCError.notPrivileged }
            try FanWriteOperations.setManualRPM(
                smc: smc,
                modeKey: modeKey,
                targetKey: targetKey,
                rpm: rpm,
                useFtst: useFtst
            )
            return
        }
        try runHelper(
            arguments: [
                "set-fan-manual-rpm",
                modeKey,
                targetKey,
                String(rpm),
                useFtst ? "1" : "0"
            ]
        )
    }

    static func setAutomatic(
        modeKeys: [String],
        clearFtst: Bool,
        using smc: SMCService? = nil
    ) throws {
        if canWriteDirectly {
            guard let smc else { throw SMCError.notPrivileged }
            try FanWriteOperations.setAutomatic(
                smc: smc,
                modeKeys: modeKeys,
                clearFtst: clearFtst
            )
            return
        }
        try runHelper(
            arguments: [
                "set-fans-auto",
                modeKeys.joined(separator: ","),
                clearFtst ? "1" : "0"
            ]
        )
    }

    static func unlockManualControl(
        modeKey: String,
        useFtst: Bool,
        using smc: SMCService? = nil
    ) throws {
        if canWriteDirectly {
            guard let smc else { throw SMCError.notPrivileged }
            try FanWriteOperations.unlockManualControl(
                smc: smc,
                modeKey: modeKey,
                useFtst: useFtst
            )
            return
        }
        try runHelper(
            arguments: [
                "unlock-manual",
                modeKey,
                useFtst ? "1" : "0"
            ]
        )
    }

    private static func runHelper(arguments: [String]) throws {
        guard PrivilegedWriteDaemon.ping(socketPath: socketPath) else {
            throw PrivilegedError.helperFailed(
                "Fan helper is not running. Click Allow fan control once."
            )
        }

        switch sendCommand(arguments) {
        case .ok:
            return
        case .disconnected:
            throw PrivilegedError.helperFailed(
                "Lost connection to the fan helper. Click Allow fan control once."
            )
        case .failed(let message):
            throw PrivilegedError.helperFailed(message)
        }
    }

    private static func sendCommand(_ arguments: [String]) -> HelperReply {
        let command = "CMD " + arguments.joined(separator: " ")
        guard let reply = PrivilegedWriteDaemon.sendCommand(socketPath: socketPath, command: command) else {
            return .disconnected
        }

        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("OK") {
            return .ok
        }
        if trimmed.hasPrefix("ERR ") {
            return .failed(String(trimmed.dropFirst(4)))
        }
        return .failed(trimmed)
    }

    private enum HelperReply {
        case ok
        case disconnected
        case failed(String)
    }

    private static func installScript(
        helperPath: String,
        socketPath: String,
        uid: uid_t,
        logPath: String
    ) -> String {
        let src = shellEscape(helperPath)
        let dest = shellEscape(PrivilegedWriteDaemon.installedHelperPath)
        let plistPath = shellEscape(PrivilegedWriteDaemon.launchdPlistPath)
        let label = shellEscape(PrivilegedWriteDaemon.launchdLabel)
        let sock = shellEscape(socketPath)
        let log = shellEscape(logPath)
        let uidArg = shellEscape(String(uid))

        return """
        #!/bin/bash
        set -euo pipefail

        SRC=\(src)
        DEST=\(dest)
        PLIST=\(plistPath)
        SOCK=\(sock)
        LOG=\(log)
        LABEL=\(label)
        UID_ARG=\(uidArg)
        PB=/usr/libexec/PlistBuddy

        /bin/mkdir -p /usr/local/libexec
        /bin/cp "$SRC" "$DEST"
        /usr/sbin/chown root:wheel "$DEST"
        /bin/chmod 755 "$DEST"

        /usr/bin/killall MacFanControlHelper >/dev/null 2>&1 || true
        /bin/rm -f "$SOCK"

        /bin/rm -f "$PLIST"
        "$PB" -c "Add :Label string $LABEL" "$PLIST"
        "$PB" -c "Add :ProgramArguments array" "$PLIST"
        "$PB" -c "Add :ProgramArguments:0 string $DEST" "$PLIST"
        "$PB" -c "Add :ProgramArguments:1 string daemon" "$PLIST"
        "$PB" -c "Add :ProgramArguments:2 string $SOCK" "$PLIST"
        "$PB" -c "Add :ProgramArguments:3 string $UID_ARG" "$PLIST"
        "$PB" -c "Add :RunAtLoad bool true" "$PLIST"
        "$PB" -c "Add :KeepAlive bool true" "$PLIST"
        "$PB" -c "Add :StandardOutPath string $LOG" "$PLIST"
        "$PB" -c "Add :StandardErrorPath string $LOG" "$PLIST"

        /usr/sbin/chown root:wheel "$PLIST"
        /bin/chmod 644 "$PLIST"

        /bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
        /bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
        if ! /bin/launchctl bootstrap system "$PLIST" >/dev/null 2>&1; then
            /bin/launchctl load -w "$PLIST"
        fi
        /bin/launchctl enable "system/$LABEL" >/dev/null 2>&1 || true
        /bin/launchctl kickstart -k "system/$LABEL" >/dev/null 2>&1 || /bin/launchctl start "$LABEL" >/dev/null 2>&1 || true

        i=0
        while [ "$i" -lt 80 ]; do
            if [ -S "$SOCK" ]; then
                exit 0
            fi
            /bin/sleep 0.1
            i=$((i + 1))
        done

        echo "helper did not create $SOCK" >&2
        /usr/bin/tail -n 20 "$LOG" >&2 || true
        exit 1
        """
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
    static var sourcePath: String? {
        candidatePaths.first { path in
            path != PrivilegedWriteDaemon.installedHelperPath
                && FileManager.default.isExecutableFile(atPath: path)
        } ?? candidatePaths.first { FileManager.default.isExecutableFile(atPath: path) }
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

        let cwd = FileManager.default.currentDirectoryPath
        appendUnique((cwd as NSString).appendingPathComponent(".build/release/\(helperName)"))
        appendUnique((cwd as NSString).appendingPathComponent(".build/out/Products/Release/\(helperName)"))

        var directory = executable.deletingLastPathComponent()
        for _ in 0..<8 {
            appendUnique(directory.appendingPathComponent(".build/release/\(helperName)").path)
            appendUnique(directory.appendingPathComponent(".build/out/Products/Release/\(helperName)").path)
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }

        appendUnique(PrivilegedWriteDaemon.installedHelperPath)
        return paths
    }
}
