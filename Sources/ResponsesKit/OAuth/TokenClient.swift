import Foundation

/// The token response from the authorization-code exchange or a refresh.
public struct TokenResponse: Decodable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let tokenType: String
    public let expiresIn: Int
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }

    public init(
        accessToken: String,
        refreshToken: String?,
        idToken: String?,
        tokenType: String,
        expiresIn: Int,
        scope: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
    }

    public var description: String {
        "TokenResponse(accessToken: <redacted>, refreshToken: <redacted>, idToken: <redacted>, "
            + "expiresIn: \(expiresIn))"
    }

    public var debugDescription: String {
        description
    }
}

/// An OAuth error from the token endpoint. `code` is the machine-readable error, such as invalid_grant.
public struct OAuthTokenError: Error, Sendable, Equatable {
    public let status: Int
    public let code: String?
    public let description: String?
}

/// Exchanges codes and refreshes tokens at the OpenAI token endpoint. The client is public: there is no secret.
public struct TokenClient: Sendable {
    public static let endpoint = "https://auth.openai.com/api/accounts/oauth/token"

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// POST authorization_code, with the issued client ID from the callback and the PKCE verifier.
    public func exchange(
        code: String,
        verifier: String,
        clientId: String,
        redirectURI: String
    ) async throws -> TokenResponse {
        try await post([
            ("grant_type", "authorization_code"),
            ("client_id", clientId),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", redirectURI),
            ("resource", AuthorizeRequest.resource)
        ])
    }

    /// POST refresh_token. The scope is left out so the existing grant is kept.
    public func refresh(refreshToken: String, clientId: String) async throws -> TokenResponse {
        try await post([
            ("grant_type", "refresh_token"),
            ("client_id", clientId),
            ("refresh_token", refreshToken),
            ("resource", AuthorizeRequest.resource)
        ])
    }

    private func post(_ pairs: [(String, String)]) async throws -> TokenResponse {
        guard let url = URL(string: Self.endpoint) else {
            throw OAuthTokenError(status: 0, code: nil, description: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = FormEncoding.body(pairs)
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 200 {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        }
        throw Self.oauthError(status: response.statusCode, body: data)
    }

    static func oauthError(status: Int, body: Data) -> OAuthTokenError {
        let parsed = try? JSONDecoder().decode(OAuthErrorBody.self, from: body)
        return OAuthTokenError(status: status, code: parsed?.error, description: parsed?.errorDescription)
    }
}

/// The error body from the token endpoint: `{"error": "...", "error_description": "..."}`.
private struct OAuthErrorBody: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
