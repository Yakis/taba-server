import Foundation

/// The secrets for one sign-in attempt. They live only until the callback completes. They are never printed.
public struct AuthorizationAttempt: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let state: String
    public let nonce: String
    public let pkce: PKCE
    /// The exact redirect URI. It must match in the authorize request and the code exchange.
    public let redirectURI: String

    public init(state: String, nonce: String, pkce: PKCE, redirectURI: String) {
        self.state = state
        self.nonce = nonce
        self.pkce = pkce
        self.redirectURI = redirectURI
    }

    /// A new attempt with fresh state, nonce and PKCE verifier.
    public static func new(redirectURI: String) -> AuthorizationAttempt {
        AuthorizationAttempt(
            state: RandomBytes.base64URLString(count: 24),
            nonce: RandomBytes.base64URLString(count: 24),
            pkce: PKCE.generate(),
            redirectURI: redirectURI
        )
    }

    public var description: String {
        "AuthorizationAttempt(state: <redacted>, nonce: <redacted>, pkce: <redacted>, redirectURI: \(redirectURI))"
    }

    public var debugDescription: String {
        description
    }
}
