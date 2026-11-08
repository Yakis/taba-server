import Crypto
import Foundation

/// PKCE (RFC 7636) with the S256 method. The verifier is secret. Only the challenge is sent to the authorize endpoint.
public struct PKCE: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let verifier: String

    public init(verifier: String) {
        self.verifier = verifier
    }

    /// A new verifier: 32 random bytes, which encode to 43 characters.
    public static func generate() -> PKCE {
        PKCE(verifier: Base64URL.encode(RandomBytes.make(count: 32)))
    }

    public var challenge: String {
        Self.challenge(for: verifier)
    }

    /// The base64url-encoded SHA-256 digest of the verifier, without padding.
    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Base64URL.encode(Data(digest))
    }

    public var description: String {
        "PKCE(verifier: <redacted>)"
    }

    public var debugDescription: String {
        description
    }
}
