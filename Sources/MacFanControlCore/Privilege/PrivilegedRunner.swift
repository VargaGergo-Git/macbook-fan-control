import Foundation
import Security

enum PrivilegedRunner {
    private static var cachedAuthorization: AuthorizationRef?

    static func withAuthorization<T>(
        prompt: String = "MacFanControl needs administrator access to change fan speeds.",
        _ work: () throws -> T
    ) throws -> T {
        try ensureAuthorization(prompt: prompt)
        return try work()
    }

    static func invalidate() {
        if let cachedAuthorization {
            AuthorizationFree(cachedAuthorization, [])
            self.cachedAuthorization = nil
        }
    }

    private static func ensureAuthorization(prompt: String) throws {
        if cachedAuthorization != nil {
            return
        }

        var authRef: AuthorizationRef?
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]

        var status = AuthorizationCreate(nil, nil, flags, &authRef)
        guard status == errAuthorizationSuccess, let authRef else {
            throw PrivilegedError.authorizationFailed
        }

        let copyStatus = kAuthorizationRightExecute.withCString { namePointer in
            var item = AuthorizationItem(
                name: namePointer,
                valueLength: 0,
                value: nil,
                flags: 0
            )

            var rights = withUnsafeMutablePointer(to: &item) { pointer in
                AuthorizationRights(count: 1, items: pointer)
            }

            return AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
        }

        status = copyStatus
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(authRef, [])
            throw PrivilegedError.authorizationDenied
        }

        cachedAuthorization = authRef
    }
}

enum PrivilegedError: Error, LocalizedError {
    case authorizationFailed
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return "Unable to request administrator authorization."
        case .authorizationDenied:
            return "Administrator authorization was denied."
        }
    }
}
