import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ResponsesKit

/// `sign-in`: opens the authorize page, waits for the loopback callback, exchanges the code and saves the credentials.
enum SignInCommand {
    static let agentNameHint = "TABA"
    static let callbackPort: UInt16 = 1455
    static let timeoutSeconds: Double = 300

    static func run() async -> Int32 {
        let store = CredentialStore.defaultStore
        let hostId: String
        let existing: ChatGPTCredentials?
        do {
            let file = try store.load()
            hostId = file?.extAgentHostId ?? CredentialFile.newHostId()
            existing = file?.credentials
        } catch {
            complain("The credentials file at \(store.url.path) cannot be read. Move it aside and sign in again.")
            return 1
        }
        // Save the host ID before the first sign-in, so it stays the same for this host.
        do {
            try store.save(CredentialFile(extAgentHostId: hostId, credentials: existing))
        } catch {
            complain("Could not write the credentials file at \(store.url.path).")
            return 1
        }
        let attempt = AuthorizationAttempt.new(redirectURI: AuthorizeRequest.redirectURI)
        let authorizeURL: URL?
        if let existing {
            authorizeURL = AuthorizeRequest.reauthorizationURL(
                attempt: attempt,
                hostId: hostId,
                clientId: existing.clientId,
                idTokenHint: existing.idToken,
                loginHint: existing.email
            )
        } else {
            authorizeURL = AuthorizeRequest.url(attempt: attempt, agentNameHint: agentNameHint, hostId: hostId)
        }
        guard let authorizeURL else {
            complain("Could not build the sign-in link.")
            return 1
        }
        print("Open this link to sign in with ChatGPT:")
        print(authorizeURL.absoluteString)
        openInBrowser(authorizeURL)

        #if canImport(Network)
        return await waitAndSave(attempt: attempt, hostId: hostId, store: store, savedClientId: existing?.clientId)
        #else
        complain("sign-in needs the Network framework, which this build does not have. Run it on macOS.")
        return 1
        #endif
    }

    static func openInBrowser(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try? process.run()
    }

    #if canImport(Network)
    private static func waitAndSave(
        attempt: AuthorizationAttempt,
        hostId: String,
        store: CredentialStore,
        savedClientId: String?
    ) async -> Int32 {
        let callback: (target: String, connection: LoopbackConnection)
        do {
            callback = try await LoopbackCallbackServer.waitForCallback(port: callbackPort, timeout: timeoutSeconds)
        } catch {
            complain("No sign-in callback arrived on 127.0.0.1:\(callbackPort): \(error).")
            return 1
        }
        let answer = AuthorizationCallback.parse(target: callback.target)
        do {
            guard let answer else { throw CallbackError.missingCode }
            let validated = try answer.validated(against: attempt)
            // A returning account keeps its saved client. A different ID from the callback is refused.
            if let returned = validated.clientId, let savedClientId, returned != savedClientId {
                throw CallbackError.clientIdMismatch
            }
            guard let clientId = validated.clientId ?? savedClientId else { throw CallbackError.missingClientId }
            let tokens = try await TokenClient().exchange(
                code: validated.code ?? "",
                verifier: attempt.pkce.verifier,
                clientId: clientId,
                redirectURI: attempt.redirectURI
            )
            let credentials = try await buildCredentials(tokens: tokens, clientId: clientId, attempt: attempt)
            try store.save(CredentialFile(extAgentHostId: hostId, credentials: credentials))
            await callback.connection.respond("Signed in, you can close this tab.")
            print("Signed in. Credentials saved to \(store.url.path).")
            if !credentials.grantsPlanUse {
                complain("ChatGPT plan use was not granted, so inference will be refused until you allow it.")
            }
            return 0
        } catch {
            await callback.connection.respond("Sign-in did not complete. Return to the terminal.")
            complain(describe(error))
            return 1
        }
    }

    private static func buildCredentials(
        tokens: TokenResponse,
        clientId: String,
        attempt: AuthorizationAttempt
    ) async throws -> ChatGPTCredentials {
        guard let idToken = tokens.idToken, let refreshToken = tokens.refreshToken else {
            throw SignInFailure.missingTokens
        }
        let jwks = try await fetchJWKS()
        let claims = try IDTokenVerifier.verify(
            idToken,
            jwks: jwks,
            clientId: clientId,
            nonce: attempt.nonce,
            now: Date()
        )
        let now = Date()
        return ChatGPTCredentials(
            email: claims.email,
            issuer: claims.issuer,
            subject: claims.subject,
            clientId: clientId,
            idToken: idToken,
            accessToken: tokens.accessToken,
            refreshToken: refreshToken,
            tokenType: tokens.tokenType,
            scopes: (tokens.scope ?? "").split(separator: " ").map(String.init),
            accessTokenExpiresAt: now.addingTimeInterval(TimeInterval(tokens.expiresIn)),
            savedAt: now
        )
    }

    private static func fetchJWKS() async throws -> JWKS {
        guard let url = URL(string: IDTokenVerifier.jwksURL) else { throw SignInFailure.missingTokens }
        let (data, response) = try await URLSessionTransport().data(for: URLRequest(url: url))
        guard response.statusCode == 200 else { throw SignInFailure.jwksUnavailable }
        return try JSONDecoder().decode(JWKS.self, from: data)
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case let error as CallbackError:
            switch error {
            case .stateMismatch: "The sign-in result did not match this attempt, so it was discarded."
            case .oauthError(let code): "Sign-in was not completed: \(code)."
            case .missingCode: "The sign-in result had no code."
            case .missingClientId: "The sign-in result had no client ID, so registration is incomplete."
            case .clientIdMismatch: "The sign-in result named a different client, so it was discarded."
            }
        case let error as OAuthTokenError:
            "The token exchange was refused (HTTP \(error.status), \(error.code ?? "no code")). Start sign-in again."
        case let error as IDTokenError:
            "The ID token could not be verified (\(error)). Nothing was saved."
        case SignInFailure.missingTokens:
            "The token response was missing tokens. Nothing was saved."
        default:
            "Sign-in failed: \(error)."
        }
    }
    #endif
}

enum SignInFailure: Error {
    case missingTokens
    case jwksUnavailable
}
