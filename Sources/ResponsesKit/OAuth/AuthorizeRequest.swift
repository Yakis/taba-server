import Foundation

/// The constants and URL of the sign-in authorize request, from the sign-in docs.
public enum AuthorizeRequest {
    public static let endpoint = "https://auth.openai.com/api/accounts/authorize"
    public static let redirectURI = "http://127.0.0.1:1455/auth/callback"
    public static let registrationClientId = "dynamic_agent_client"
    public static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public static let resource = "https://api.openai.com/v1"

    /// The authorize URL for a first-time registration. `agentNameHint` is the app's name and `hostId` is the stable
    /// `ext_agent_host_id`. The URL carries state, nonce and the PKCE challenge, but never the verifier.
    public static func url(attempt: AuthorizationAttempt, agentNameHint: String, hostId: String) -> URL? {
        let pairs: [(String, String)] = [
            ("client_id", registrationClientId),
            ("agent_name_hint", agentNameHint),
            ("ext_agent_host_id", hostId),
            ("response_type", "code"),
            ("redirect_uri", attempt.redirectURI),
            ("scope", scope),
            ("resource", resource),
            ("state", attempt.state),
            ("nonce", attempt.nonce),
            ("code_challenge_method", "S256"),
            ("code_challenge", attempt.pkce.challenge)
        ]
        let query = pairs
            .map { "\(FormEncoding.encode($0.0))=\(FormEncoding.encode($0.1))" }
            .joined(separator: "&")
        return URL(string: "\(endpoint)?\(query)")
    }
}

extension AuthorizeRequest {
    /// The authorize URL for a returning account: the saved issued client ID, no agent name, and the retained ID token
    /// and email as hints. The docs ask for this instead of a new registration.
    public static func reauthorizationURL(
        attempt: AuthorizationAttempt,
        hostId: String,
        clientId: String,
        idTokenHint: String?,
        loginHint: String?
    ) -> URL? {
        var pairs: [(String, String)] = [
            ("client_id", clientId),
            ("ext_agent_host_id", hostId),
            ("response_type", "code"),
            ("redirect_uri", attempt.redirectURI),
            ("scope", scope),
            ("resource", resource),
            ("state", attempt.state),
            ("nonce", attempt.nonce),
            ("code_challenge_method", "S256"),
            ("code_challenge", attempt.pkce.challenge)
        ]
        if let idTokenHint { pairs.append(("id_token_hint", idTokenHint)) }
        if let loginHint { pairs.append(("login_hint", loginHint)) }
        let query = pairs
            .map { "\(FormEncoding.encode($0.0))=\(FormEncoding.encode($0.1))" }
            .joined(separator: "&")
        return URL(string: "\(endpoint)?\(query)")
    }
}
