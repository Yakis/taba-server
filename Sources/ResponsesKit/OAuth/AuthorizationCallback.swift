import Foundation

/// The parameters the browser returns to the loopback callback.
public struct AuthorizationCallback: Sendable, Equatable {
    public let code: String?
    public let state: String?
    public let error: String?
    /// The issued client ID. Present on a new registration, and it must match the one on record.
    public let clientId: String?
    public let scope: String?

    public init(code: String?, state: String?, error: String?, clientId: String?, scope: String?) {
        self.code = code
        self.state = state
        self.error = error
        self.clientId = clientId
        self.scope = scope
    }

    /// Reads the query of a callback target such as "/auth/callback?code=...&state=...".
    public static func parse(target: String) -> AuthorizationCallback? {
        guard let components = URLComponents(string: "http://127.0.0.1" + target) else { return nil }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            values[item.name] = item.value
        }
        return AuthorizationCallback(
            code: values["code"],
            state: values["state"],
            error: values["error"],
            clientId: values["client_id"],
            scope: values["scope"]
        )
    }
}

public enum CallbackError: Error, Sendable, Equatable {
    /// The state does not match this attempt. The result must not be used.
    case stateMismatch
    /// The browser returned an OAuth error, such as access_denied. Nothing is exchanged.
    case oauthError(String)
    case missingCode
    case missingClientId
    /// The callback names a different client ID from the saved one. The result is discarded.
    case clientIdMismatch
}

extension AuthorizationCallback {
    /// Checks the callback against the attempt. Returns the callback when it is valid and carries a code.
    public func validated(against attempt: AuthorizationAttempt) throws(CallbackError) -> AuthorizationCallback {
        guard let state, state == attempt.state else {
            throw CallbackError.stateMismatch
        }
        if let error {
            throw CallbackError.oauthError(error)
        }
        guard code != nil else {
            throw CallbackError.missingCode
        }
        return self
    }
}
