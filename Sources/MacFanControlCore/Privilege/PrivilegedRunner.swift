import Foundation

enum PrivilegedRunner {
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
            return "Administrator authorization was canceled."
        case .helperMissing:
            return "MacFanControlHelper not found. Rebuild with: swift build -c release\nThen run: ./scripts/run.sh"
        case .helperFailed(let message):
            return message
        }
    }
}
