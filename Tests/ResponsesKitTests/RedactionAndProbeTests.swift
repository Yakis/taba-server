import Foundation
import ResponsesKit
import Testing

struct RedactionTests {
    private let secrets = ["access-token-secret-0001", "refresh-token-secret-0001", "id-token-secret-0001",
                           "oaiapp_secret_client_0001", // privacy-scan:allow
                           "subject-secret-0001", "state-secret-0001",
                           "nonce-secret-0001", "verifier-secret-0001"]

    private func assertRedacted(_ text: String) {
        for secret in secrets {
            #expect(!text.contains(secret), "\(secret) leaked")
        }
    }

    @Test func credentialsNeverShowTheirTokens() {
        let credentials = ChatGPTCredentials(
            email: nil, issuer: "https://auth.openai.com", subject: "subject-secret-0001",
            clientId: "oaiapp_secret_client_0001", idToken: "id-token-secret-0001", // privacy-scan:allow
            accessToken: "access-token-secret-0001", refreshToken: "refresh-token-secret-0001",
            tokenType: "Bearer", scopes: [], accessTokenExpiresAt: Date(), savedAt: Date()
        )
        assertRedacted("\(credentials) \(String(reflecting: credentials))")
    }

    @Test func attemptAndPKCENeverShowTheirSecrets() {
        let attempt = AuthorizationAttempt(
            state: "state-secret-0001", nonce: "nonce-secret-0001",
            pkce: PKCE(verifier: "verifier-secret-0001"), redirectURI: AuthorizeRequest.redirectURI
        )
        assertRedacted("\(attempt) \(String(reflecting: attempt)) \(attempt.pkce) \(String(reflecting: attempt.pkce))")
    }

    @Test func tokenResponseAndFileNeverShowTheirTokens() {
        let response = TokenResponse(
            accessToken: "access-token-secret-0001", refreshToken: "refresh-token-secret-0001",
            idToken: "id-token-secret-0001", tokenType: "Bearer", expiresIn: 3600, scope: nil
        )
        let file = CredentialFile(extAgentHostId: "urn:uuid:0001", credentials: nil)
        assertRedacted("\(response) \(String(reflecting: response)) \(file)")
    }

}

struct ProbeCheckTests {
    @Test func aValidPlanPassesEveryCheck() {
        let text = """
        {"days":[{"date":"2025-11-23","stops":[{"placeId":"osm:node/1","kind":"sight",
        "start":"10:00","minutes":60,"reason":"Market."}]}],"openQuestions":[]}
        """
        let check = ProbeChecks.planDraft(text, candidateIds: ["osm:node/1"])
        #expect(check.decodes)
        #expect(check.schemaValid)
        #expect(check.placeIdsFromCandidates)
        #expect(check.stopCount == 1)
    }

    @Test func aPlaceIdOutsideTheCandidatesIsFlagged() {
        let text = """
        {"days":[{"date":"2025-11-23","stops":[{"placeId":"osm:node/9","kind":"sight",
        "start":"10:00","minutes":60,"reason":"x"}]}],"openQuestions":[]}
        """
        let check = ProbeChecks.planDraft(text, candidateIds: ["osm:node/1"])
        #expect(!check.placeIdsFromCandidates)
        #expect(check.problems.contains { $0.contains("osm:node/9") })
    }

    @Test func aBadClockTimeIsFlagged() {
        let text = """
        {"days":[{"date":"2025-11-23","stops":[{"placeId":"osm:node/1","kind":"sight",
        "start":"9:99","minutes":60,"reason":"x"}]}],"openQuestions":[]}
        """
        let check = ProbeChecks.planDraft(text, candidateIds: ["osm:node/1"])
        #expect(!check.schemaValid)
    }

    @Test func notJSONDoesNotDecode() {
        let check = ProbeChecks.planDraft("Here is your plan.", candidateIds: [])
        #expect(!check.decodes)
    }

    @Test func researchURLsMustBeAmongTheSources() {
        let text = """
        {"findings":[{"title":"Markets","url":"https://edinburgh.org/things-to-do/markets/","summary":"Sundays."},
        {"title":"Other","url":"https://example.com/made-up","summary":"x"}],"searchNotes":"ok"}
        """
        let check = ProbeChecks.research(text, sourceURLs: ["https://edinburgh.org/things-to-do/markets"])
        #expect(check.findingCount == 2)
        #expect(check.findingsWithSourceURL == 1)
        #expect(check.unmatchedURLs == ["https://example.com/made-up"])
    }

    @Test func promptBodyDropsTheFrontMatter() {
        let text = "---\nid: plan\nversion: 1\n---\n\nYou plan the days.\n"
        #expect(PromptFile.body(of: text) == "You plan the days.")
    }

    @Test func promptWithoutFrontMatterIsKeptWhole() {
        #expect(PromptFile.body(of: "Just instructions.\n") == "Just instructions.")
    }
}
