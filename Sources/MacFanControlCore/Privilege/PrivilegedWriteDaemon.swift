import Foundation
import Darwin

/// Root helper that stays alive after one administrator prompt.
/// Later fan writes go over a unix socket so the slider does not ask for a password again.
enum PrivilegedWriteDaemon {
    static func socketPath(for uid: uid_t = getuid()) -> String {
        "/tmp/macfancontrol-\(uid).sock"
    }

    static func run(socketPath: String, allowedUID: uid_t) throws {
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
        chown(socketPath, allowedUID, gid)
        chmod(socketPath, 0o600)

        guard listen(server, 8) == 0 else {
            close(server)
            unlink(socketPath)
            throw DaemonError.posix("listen", errno)
        }

        FileHandle.standardError.write(Data("listening \(socketPath)\n".utf8))

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
