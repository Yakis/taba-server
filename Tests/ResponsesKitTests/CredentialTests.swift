import Foundation
import ResponsesKit
import Testing

struct CredentialStoreTests {
    private func credentials(expiresIn seconds: TimeInterval, now: Date) -> ChatGPTCredentials {
        ChatGPTCredentials(
            email: "tester@example.com",
            issuer: "https://auth.openai.com",
            subject: "test-subject-0001",
            clientId: "oaiapp_test_0001", // privacy-scan:allow
            idToken: "id-token-fake-0001",
            accessToken: "access-token-fake-0001",
            refreshToken: "refresh-token-fake-0001",
            tokenType: "Bearer",
            scopes: ["chatgpt.tokens.use.direct", "offline_access"],
            accessTokenExpiresAt: now.addingTimeInterval(seconds),
            savedAt: now
        )
    }

    @Test func roundTripsTheFile() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CredentialStore(url: folder.url.appendingPathComponent("nested/chatgpt.json"))
        let now = Date(timeIntervalSince1970: 1_767_300_000)
        let file = CredentialFile(extAgentHostId: "urn:uuid:0001", credentials: credentials(expiresIn: 3600, now: now))
        try store.save(file)
        let loaded = try #require(try store.load())
        #expect(loaded == file)
    }

    @Test func missingFileLoadsAsNil() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CredentialStore(url: folder.url.appendingPathComponent("chatgpt.json"))
        #expect(try store.load() == nil)
    }

    @Test func fileIsOwnerOnlyAndFolderIsOwnerOnly() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let directory = folder.url.appendingPathComponent("private", isDirectory: true)
        let fileURL = directory.appendingPathComponent("chatgpt.json")
        let store = CredentialStore(url: fileURL)
        try store.save(CredentialFile(extAgentHostId: "urn:uuid:0001", credentials: nil))
        let fileMode = try permissions(of: fileURL)
        let folderMode = try permissions(of: directory)
        #expect(fileMode == 0o600)
        #expect(folderMode == 0o700)
    }

    @Test func overridePathComesFromTheEnvironment() {
        let url = CredentialStore.defaultURL(
            environment: ["TABA_CHATGPT_CREDENTIALS": "/tmp/override-chatgpt.json"],
            home: URL(fileURLWithPath: "/home/tester")
        )
        #expect(url.path == "/tmp/override-chatgpt.json")
    }

    @Test func defaultPathIsUnderTheHomeConfigFolder() {
        let url = CredentialStore.defaultURL(environment: [:], home: URL(fileURLWithPath: "/home/tester"))
        #expect(url.path == "/home/tester/.config/taba/chatgpt.json") // privacy-scan:allow
    }

    @Test func hostIdIsAUUIDURN() throws {
        let hostId = CredentialFile.newHostId()
        #expect(hostId.hasPrefix("urn:uuid:"))
        #expect(UUID(uuidString: String(hostId.dropFirst("urn:uuid:".count))) != nil)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

struct RefreshTimingTests {
    @Test func refreshesWhenLessThanFiveMinutesRemain() {
        let now = Date(timeIntervalSince1970: 1_767_300_000)
        let expiring = makeCredentials(expiresAt: now.addingTimeInterval(299))
        let fresh = makeCredentials(expiresAt: now.addingTimeInterval(301))
        #expect(expiring.needsRefresh(now: now))
        #expect(!fresh.needsRefresh(now: now))
    }

    @Test func expiredTokenNeedsRefresh() {
        let now = Date(timeIntervalSince1970: 1_767_300_000)
        #expect(makeCredentials(expiresAt: now.addingTimeInterval(-10)).needsRefresh(now: now))
    }

    @Test func planUseComesFromTheGrantedScopes() {
        let now = Date(timeIntervalSince1970: 1_767_300_000)
        #expect(makeCredentials(expiresAt: now).grantsPlanUse)
    }

    private func makeCredentials(expiresAt: Date) -> ChatGPTCredentials {
        ChatGPTCredentials(
            email: nil,
            issuer: "https://auth.openai.com",
            subject: "test-subject-0001",
            clientId: "oaiapp_test_0001", // privacy-scan:allow
            idToken: "id-token-fake-0001",
            accessToken: "access-token-fake-0001",
            refreshToken: "refresh-token-fake-0001",
            tokenType: "Bearer",
            scopes: ["chatgpt.tokens.use.direct"],
            accessTokenExpiresAt: expiresAt,
            savedAt: expiresAt
        )
    }
}

struct CredentialSessionTests {
    private let refreshedTokens = #"{"access_token":"access-token-new","# // privacy-scan:allow
        + #""refresh_token":"refresh-token-new","# // privacy-scan:allow
        + #""token_type":"Bearer","expires_in":3600}"#

    @Test func refreshReplacesTokensSavesThemAndKeepsTheIssuedClientId() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CredentialStore(url: folder.url.appendingPathComponent("chatgpt.json"))
        let now = Date(timeIntervalSince1970: 1_767_300_000)
        let old = ChatGPTCredentials(
            email: nil,
            issuer: "https://auth.openai.com",
            subject: "test-subject-0001",
            clientId: "oaiapp_test_0001", // privacy-scan:allow
            idToken: "id-token-old",
            accessToken: "access-token-old",
            refreshToken: "refresh-token-old",
            tokenType: "Bearer",
            scopes: ["chatgpt.tokens.use.direct"],
            accessTokenExpiresAt: now.addingTimeInterval(60),
            savedAt: now
        )
        try store.save(CredentialFile(extAgentHostId: "urn:uuid:0001", credentials: old))

        let transport = FakeHTTPTransport { _ in
            (200, Data(refreshedTokens.utf8))
        }
        let session = CredentialSession(store: store, tokenClient: TokenClient(transport: transport), clock: { now })
        let refreshed = try await session.credentials()

        #expect(refreshed.accessToken == "access-token-new")
        #expect(refreshed.refreshToken == "refresh-token-new")
        #expect(refreshed.idToken == "id-token-old")
        #expect(refreshed.clientId == "oaiapp_test_0001") // privacy-scan:allow
        let saved = try #require(try store.load())
        #expect(saved.credentials?.accessToken == "access-token-new")
        #expect(saved.extAgentHostId == "urn:uuid:0001")

        let sent = transport.requests.first?.httpBody ?? Data()
        let body = String(data: sent, encoding: .utf8) ?? ""
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("client_id=oaiapp_test_0001")) // privacy-scan:allow
        #expect(body.contains("resource=https%3A%2F%2Fapi.openai.com%2Fv1"))
        #expect(!body.contains("scope="))
        #expect(!body.contains("dynamic_agent_client"))
    }

    @Test func aFreshTokenIsNotRefreshed() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CredentialStore(url: folder.url.appendingPathComponent("chatgpt.json"))
        let now = Date(timeIntervalSince1970: 1_767_300_000)
        let fresh = ChatGPTCredentials(
            email: nil,
            issuer: "https://auth.openai.com",
            subject: "test-subject-0001",
            clientId: "oaiapp_test_0001", // privacy-scan:allow
            idToken: "id-token-fake-0001",
            accessToken: "access-token-fresh",
            refreshToken: "refresh-token-fake-0001",
            tokenType: "Bearer",
            scopes: ["chatgpt.tokens.use.direct"],
            accessTokenExpiresAt: now.addingTimeInterval(3600),
            savedAt: now
        )
        try store.save(CredentialFile(extAgentHostId: "urn:uuid:0001", credentials: fresh))
        let transport = FakeHTTPTransport { _ in (500, Data()) }
        let session = CredentialSession(store: store, tokenClient: TokenClient(transport: transport), clock: { now })
        let credentials = try await session.credentials()
        #expect(credentials.accessToken == "access-token-fresh")
        #expect(transport.requests.isEmpty)
    }

    @Test func invalidGrantIsReportedWithItsCode() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CredentialStore(url: folder.url.appendingPathComponent("chatgpt.json"))
        let now = Date(timeIntervalSince1970: 1_767_300_000)
        let old = ChatGPTCredentials(
            email: nil,
            issuer: "https://auth.openai.com",
            subject: "test-subject-0001",
            clientId: "oaiapp_test_0001", // privacy-scan:allow
            idToken: "id-token-old",
            accessToken: "access-token-old",
            refreshToken: "refresh-token-old",
            tokenType: "Bearer",
            scopes: [],
            accessTokenExpiresAt: now,
            savedAt: now
        )
        try store.save(CredentialFile(extAgentHostId: "urn:uuid:0001", credentials: old))
        let transport = FakeHTTPTransport { _ in (400, Data(#"{"error":"invalid_grant"}"#.utf8)) }
        let session = CredentialSession(store: store, tokenClient: TokenClient(transport: transport), clock: { now })
        await #expect(throws: CredentialSessionError.refreshFailed(code: "invalid_grant")) {
            _ = try await session.credentials()
        }
    }

    @Test func noFileMeansNotSignedIn() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CredentialStore(url: folder.url.appendingPathComponent("chatgpt.json"))
        let transport = FakeHTTPTransport { _ in (500, Data()) }
        let session = CredentialSession(store: store, tokenClient: TokenClient(transport: transport))
        await #expect(throws: CredentialSessionError.notSignedIn) {
            _ = try await session.credentials()
        }
    }
}
