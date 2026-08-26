import Foundation

enum PrivilegedRunner {
    static func withAuthorization<T>(
        prompt: String = "MacFanControl needs administrator access to change fan speeds.",
        _ work: () throws -> T
    ) throws -> T {
        if PrivilegedSMC.canWriteDirectly {
            return try work()
        }
        return try work()
    }

    static func invalidate() {}
}

enum PrivilegedError: Error, LocalizedError {
    case authorizationFailed
    case authorizationDenied
    case helperMissing
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return "Unable to request administrator authorization."
        case .authorizationDenied:
            return "Administrator authorization was denied."
        case .helperMissing:
            return "MacFanControlHelper not found next to the app. Rebuild with swift build -c release."
        case .helperFailed(let message):
            return message
        }
    }
}
