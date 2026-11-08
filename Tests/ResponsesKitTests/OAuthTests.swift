import Foundation
import ResponsesKit
import Testing

struct PKCETests {
    @Test func s256MatchesTheRFC7636Vector() {
        // RFC 7636, appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifierHasTheRightLengthAndAlphabet() {
        let pkce = PKCE.generate()
        #expect(pkce.verifier.count == 43)
        #expect(pkce.verifier.allSatisfy { $0.isLetter || $0.isNumber || "-_".contains($0) })
        #expect(pkce.challenge.count == 43)
    }

    @Test func generatedAttemptsAreDifferent() {
        let first = AuthorizationAttempt.new(redirectURI: AuthorizeRequest.redirectURI)
        let second = AuthorizationAttempt.new(redirectURI: AuthorizeRequest.redirectURI)
        #expect(first.state != second.state)
        #expect(first.nonce != second.nonce)
        #expect(first.pkce.verifier != second.pkce.verifier)
    }
}

struct AuthorizeRequestTests {
    private func query(_ url: URL) -> [String: String] {
        var values: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            values[item.name] = item.value
        }
        return values
    }

    @Test func carriesEveryRequiredParameter() throws {
        let attempt = AuthorizationAttempt(
            state: "state-0001",
            nonce: "nonce-0001",
            pkce: PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            redirectURI: AuthorizeRequest.redirectURI
        )
        let url = try #require(AuthorizeRequest.url(attempt: attempt, agentNameHint: "TABA", hostId: "urn:uuid:0001"))
        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/api/accounts/authorize?"))
        let values = query(url)
        #expect(values["client_id"] == "dynamic_agent_client")
        #expect(values["agent_name_hint"] == "TABA")
        #expect(values["ext_agent_host_id"] == "urn:uuid:0001")
        #expect(values["response_type"] == "code")
        #expect(values["redirect_uri"] == "http://127.0.0.1:1455/auth/callback")
        #expect(values["scope"] == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        #expect(values["resource"] == "https://api.openai.com/v1")
        #expect(values["state"] == "state-0001")
        #expect(values["nonce"] == "nonce-0001")
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["code_challenge"] == attempt.pkce.challenge)
    }

    @Test func neverSendsTheVerifier() throws {
        let attempt = AuthorizationAttempt.new(redirectURI: AuthorizeRequest.redirectURI)
        let url = try #require(AuthorizeRequest.url(attempt: attempt, agentNameHint: "TABA", hostId: "urn:uuid:0001"))
        #expect(!url.absoluteString.contains(attempt.pkce.verifier))
        #expect(query(url)["code_verifier"] == nil)
    }
}

struct CallbackTests {
    private let attempt = AuthorizationAttempt(
        state: "state-0001",
        nonce: "nonce-0001",
        pkce: PKCE(verifier: "verifier-0001"),
        redirectURI: AuthorizeRequest.redirectURI
    )

    @Test func matchingStateAndCodePass() throws {
        let callback = try #require(AuthorizationCallback.parse(
            target: "/auth/callback?code=code-0001&state=state-0001&client_id=oaiapp_test_0001" // privacy-scan:allow
        ))
        let validated = try callback.validated(against: attempt)
        #expect(validated.code == "code-0001")
        #expect(validated.clientId == "oaiapp_test_0001") // privacy-scan:allow
    }

    @Test func stateMismatchIsRejected() throws {
        let callback = try #require(AuthorizationCallback.parse(target: "/auth/callback?code=c&state=other"))
        #expect(throws: CallbackError.stateMismatch) {
            _ = try callback.validated(against: attempt)
        }
    }

    @Test func missingStateIsRejected() throws {
        let callback = try #require(AuthorizationCallback.parse(target: "/auth/callback?code=c"))
        #expect(throws: CallbackError.stateMismatch) {
            _ = try callback.validated(against: attempt)
        }
    }

    @Test func declinedConsentIsAnOAuthError() throws {
        let callback = try #require(AuthorizationCallback.parse(
            target: "/auth/callback?error=access_denied&state=state-0001"
        ))
        #expect(throws: CallbackError.oauthError("access_denied")) {
            _ = try callback.validated(against: attempt)
        }
    }

    @Test func noCodeIsRejected() throws {
        let callback = try #require(AuthorizationCallback.parse(target: "/auth/callback?state=state-0001"))
        #expect(throws: CallbackError.missingCode) {
            _ = try callback.validated(against: attempt)
        }
    }
}

struct ReauthorizationTests {
    @Test func aReturningAccountUsesItsSavedClientAndHints() throws {
        let attempt = AuthorizationAttempt.new(redirectURI: AuthorizeRequest.redirectURI)
        let url = try #require(AuthorizeRequest.reauthorizationURL(
            attempt: attempt,
            hostId: "urn:uuid:0001",
            clientId: "oaiapp_saved_0001", // privacy-scan:allow
            idTokenHint: "id-token-hint-0001",
            loginHint: "tester@example.com"
        ))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let names = Set(items.map(\.name))
        #expect(items.first { $0.name == "client_id" }?.value == "oaiapp_saved_0001") // privacy-scan:allow
        #expect(items.first { $0.name == "id_token_hint" }?.value == "id-token-hint-0001")
        #expect(items.first { $0.name == "login_hint" }?.value == "tester@example.com")
        #expect(!names.contains("agent_name_hint"))
        #expect(!names.contains("code_verifier"))
    }
}
