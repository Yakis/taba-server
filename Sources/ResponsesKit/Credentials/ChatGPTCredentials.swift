import Foundation

/// The signed-in account's tokens and what was granted. Tokens are secret: the description and debug description
/// never show them.
public struct ChatGPTCredentials: Codable, Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let email: String?
    public let issuer: String
    public let subject: String
    /// The issued client ID from the registration. It is not `dynamic_agent_client`.
    public let clientId: String
    public let idToken: String
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let scopes: [String]
    public let accessTokenExpiresAt: Date
    public let savedAt: Date

    public init(
        email: String?,
        issuer: String,
        subject: String,
        clientId: String,
        idToken: String,
        accessToken: String,
        refreshToken: String,
        tokenType: String,
        scopes: [String],
        accessTokenExpiresAt: Date,
        savedAt: Date
    ) {
        self.email = email
        self.issuer = issuer
        self.subject = subject
        self.clientId = clientId
        self.idToken = idToken
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scopes = scopes
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.savedAt = savedAt
    }

    /// True when the access token expires within `margin` seconds of `now`. The default margin is 5 minutes.
    public func needsRefresh(now: Date, margin: TimeInterval = 300) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) < margin
    }

    /// True when the granted scopes include ChatGPT plan usage. Inference is refused without it.
    public var grantsPlanUse: Bool {
        scopes.contains("chatgpt.tokens.use.direct")
    }

    public var description: String {
        "ChatGPTCredentials(subject: <redacted>, clientId: <redacted>, tokens: <redacted>, "
            + "accessTokenExpiresAt: \(accessTokenExpiresAt), scopes: \(scopes.count))"
    }

    public var debugDescription: String {
        description
    }
}

/// What the credentials file holds: the host ID, which exists before sign-in, and the credentials once signed in.
public struct CredentialFile: Codable, Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let extAgentHostId: String
    public let credentials: ChatGPTCredentials?

    public init(extAgentHostId: String, credentials: ChatGPTCredentials?) {
        self.extAgentHostId = extAgentHostId
        self.credentials = credentials
    }

    /// A new host ID in the `urn:uuid:` form the docs accept. Generated once and reused for this host.
    public static func newHostId() -> String {
        "urn:uuid:\(UUID().uuidString.lowercased())"
    }

    public var description: String {
        "CredentialFile(extAgentHostId: <redacted>, credentials: \(credentials == nil ? "none" : "<redacted>"))"
    }

    public var debugDescription: String {
        description
    }
}
