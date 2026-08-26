import Foundation
import Darwin

/// Root helper that stays alive after one administrator prompt.
/// Later fan writes go over a unix socket so the slider does not ask for a password again.
enum PrivilegedWriteDaemon {
    private static let daemonizedKey = "MACFANCONTROL_DAEMONIZED"
    private static let launchdLabel = "com.macfancontrol.helper"
    private static let launchdPlistPath = "/Library/LaunchDaemons/com.macfancontrol.helper.plist"

    static func socketPath(for uid: uid_t = getuid()) -> String {
        "/tmp/macfancontrol-\(uid).sock"
    }

    /// Returns `true` when this process should stay and listen.
    /// Returns `false` after spawning a detached child (parent should exit 0).
    static func detachIfNeeded(socketPath: String, allowedUID: uid_t) throws -> Bool {
        if ProcessInfo.processInfo.environment[daemonizedKey] == "1" {
            return true
        }

        if ping(socketPath: socketPath) {
            FileHandle.standardError.write(Data("already-running\n".utf8))
            return false
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        var environment = ProcessInfo.processInfo.environment
        environment[daemonizedKey] = "1"

        try spawnDetached(
            executable: executable,
            arguments: [executable, "daemon", socketPath, String(allowedUID)],
            environment: environment
        )
        return false
    }

    static func run(socketPath: String, allowedUID: uid_t) throws {
        signal(SIGHUP, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)

        if ping(socketPath: socketPath) {
            FileHandle.standardError.write(Data("already-running\n".utf8))
            return
        }

        unlink(socketPath)

        let smc = SMCService()
        try smc.open()
        defer { smc.close() }

        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0 else {
            throw DaemonError.posix("socket", errno)
        }

        var addr = makeAddress(socketPath)
        let bindResult = withSockaddr(&addr) { pointer, length in
            Darwin.bind(server, pointer, length)
        }
        guard bindResult == 0 else {
            close(server)
            throw DaemonError.posix("bind", errno)
        }

        let gid = groupID(for: allowedUID)
        _ = chown(socketPath, allowedUID, gid)
        chmod(socketPath, 0o600)

        guard listen(server, 8) == 0 else {
            close(server)
            unlink(socketPath)
            throw DaemonError.posix("listen", errno)
        }

        FileHandle.standardError.write(Data("listening \(socketPath)\n".utf8))
        installKeepAlive(
            executable: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path,
            socketPath: socketPath,
            uid: allowedUID
        )

        while true {
            let client = accept(server, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }

            let shouldStop = handleClient(client, smc: smc, allowedUID: allowedUID)
            close(client)
            if shouldStop { break }
        }

        close(server)
        unlink(socketPath)
    }

    static func ping(socketPath: String, timeoutSeconds: TimeInterval = 0.35) -> Bool {
        transmit(socketPath: socketPath, line: "PING\n", timeoutSeconds: timeoutSeconds)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("OK") == true
    }

    static func sendCommand(socketPath: String, command: String, timeoutSeconds: TimeInterval = 12) -> String? {
        let line = command.hasSuffix("\n") ? command : command + "\n"
        return transmit(socketPath: socketPath, line: line, timeoutSeconds: timeoutSeconds)
    }

    static func quit(socketPath: String) {
        _ = transmit(socketPath: socketPath, line: "QUIT\n", timeoutSeconds: 1)
    }

    private static func spawnDetached(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws {
        var attr = posix_spawnattr_t()
        let initStatus = posix_spawnattr_init(&attr)
        guard initStatus == 0 else {
            throw DaemonError.posix("spawnattr_init", initStatus)
        }
        defer { posix_spawnattr_destroy(&attr) }

        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var fileActions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)

        var argv = arguments.map { strdup($0) }
        argv.append(nil)
        defer {
            for pointer in argv where pointer != nil {
                free(pointer)
            }
        }

        var envp = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            for pointer in envp where pointer != nil {
                free(pointer)
            }
        }

        var pid: pid_t = 0
        let status = executable.withCString { path in
            argv.withUnsafeMutableBufferPointer { argvBuffer in
                envp.withUnsafeMutableBufferPointer { envBuffer in
                    posix_spawn(
                        &pid,
                        path,
                        &fileActions,
                        &attr,
                        argvBuffer.baseAddress,
                        envBuffer.baseAddress
                    )
                }
            }
        }

        guard status == 0 else {
            throw DaemonError.posix("posix_spawn", status)
        }
    }

    private static func installKeepAlive(executable: String, socketPath: String, uid: uid_t) {
        guard geteuid() == 0 else { return }

        let logPath = "/tmp/macfancontrol-\(uid).log"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchdLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscape(executable))</string>
                <string>daemon</string>
                <string>\(xmlEscape(socketPath))</string>
                <string>\(uid)</string>
            </array>
            <key>EnvironmentVariables</key>
            <dict>
                <key>\(daemonizedKey)</key>
                <string>1</string>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>StandardOutPath</key>
            <string>\(xmlEscape(logPath))</string>
            <key>StandardErrorPath</key>
            <string>\(xmlEscape(logPath))</string>
        </dict>
        </plist>
        """

        do {
            try plist.write(toFile: launchdPlistPath, atomically: true, encoding: .utf8)
            chown(launchdPlistPath, 0, 0)
            chmod(launchdPlistPath, 0o644)
            _ = launchctl(["bootout", "system/\(launchdLabel)"])
            _ = launchctl(["bootstrap", "system", launchdPlistPath])
            FileHandle.standardError.write(Data("launchd installed\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("launchd install skipped: \(error.localizedDescription)\n".utf8))
        }
    }

    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func handleClient(_ fd: Int32, smc: SMCService, allowedUID: uid_t) -> Bool {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        if getpeereid(fd, &peerUID, &peerGID) == 0, peerUID != allowedUID, peerUID != 0 {
            writeReply(fd, "ERR unauthorized\n")
            return false
        }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.recv(fd, &buffer, buffer.count - 1, 0)
        guard count > 0, let raw = String(bytes: buffer.prefix(Int(count)), encoding: .utf8) else {
            writeReply(fd, "ERR empty\n")
            return false
        }

        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard let verb = parts.first else {
            writeReply(fd, "ERR empty\n")
            return false
        }

        switch verb {
        case "PING":
            writeReply(fd, "OK\n")
            return false
        case "QUIT":
            writeReply(fd, "OK bye\n")
            return true
        case "CMD":
            do {
                try MacFanControlHelperCLI.execute(arguments: Array(parts.dropFirst()), smc: smc)
                writeReply(fd, "OK\n")
            } catch {
                writeReply(fd, "ERR \(error.localizedDescription)\n")
            }
            return false
        default:
            writeReply(fd, "ERR unknown \(verb)\n")
            return false
        }
    }

    private static func transmit(socketPath: String, line: String, timeoutSeconds: TimeInterval) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        let seconds = Int(timeoutSeconds)
        let microseconds = Int32(max(0, (timeoutSeconds - Double(seconds)) * 1_000_000))
        var timeout = timeval(tv_sec: seconds, tv_usec: microseconds)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = makeAddress(socketPath)
        let connected = withSockaddr(&addr) { pointer, length in
            Darwin.connect(fd, pointer, length)
        }
        guard connected == 0 else { return nil }

        let payload = Array(line.utf8)
        let sent = payload.withUnsafeBufferPointer { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
        }
        guard sent == payload.count else { return nil }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = Darwin.recv(fd, &buffer, buffer.count - 1, 0)
        guard received > 0 else { return nil }
        return String(bytes: buffer.prefix(Int(received)), encoding: .utf8)
    }

    private static func makeAddress(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        _ = path.withCString { source in
            withUnsafeMutablePointer(to: &addr.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: 104) { chars in
                    strncpy(chars, source, 103)
                }
            }
        }
        return addr
    }

    private static func withSockaddr(
        _ addr: inout sockaddr_un,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32
    ) -> Int32 {
        withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                body(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    private static func writeReply(_ fd: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBufferPointer { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
        }
    }

    private static func groupID(for uid: uid_t) -> gid_t {
        guard let password = getpwuid(uid) else { return 0 }
        return password.pointee.pw_gid
    }
}

enum DaemonError: Error, LocalizedError {
    case posix(String, Int32)

    var errorDescription: String? {
        switch self {
        case .posix(let name, let code):
            let message = String(cString: strerror(code))
            return "Helper \(name) failed: \(message)"
        }
    }
}
