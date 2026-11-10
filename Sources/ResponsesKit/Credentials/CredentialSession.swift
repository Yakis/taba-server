import Foundation

public enum CredentialSessionError: Error, Sendable, Equatable {
    /// No credentials file, or the file has no signed-in account. Run sign-in first.
    case notSignedIn
    /// The file is there but cannot be read.
    case unreadable
    /// The refresh was refused. `code` is the OAuth error, such as invalid_grant.
    case refreshFailed(code: String?)
    /// The refresh response did not carry usable tokens.
    case refreshIncomplete
    case saveFailed
}

/// Gives callers credentials that are valid now, refreshing and saving them when needed. An actor, and one refresh
/// at a time: concurrent callers share the refresh in flight, so a rotating refresh token is never sent twice.
public actor CredentialSession {
    private let store: CredentialStore
    private let tokenClient: TokenClient
    private let clock: @Sendable () -> Date
    /// The refresh in progress, if any, so that concurrent callers wait for it instead of refreshing again.
    private var refreshing: Task<Result<ChatGPTCredentials, CredentialSessionError>, Never>?

    public init(store: CredentialStore, tokenClient: TokenClient, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.tokenClient = tokenClient
        self.clock = clock
    }

    /// The saved credentials, refreshed first when they expire within five minutes or when `forceRefresh` is set.
    public func credentials(forceRefresh: Bool = false) async throws(CredentialSessionError) -> ChatGPTCredentials {
        let file: CredentialFile?
        do {
            file = try store.load()
        } catch {
            throw .unreadable
        }
        guard let current = file?.credentials, let hostId = file?.extAgentHostId else {
            throw .notSignedIn
        }
        let now = clock()
        guard forceRefresh || current.needsRefresh(now: now) else {
            return current
        }
        // The refresh suspends, so another caller could reach this point meanwhile. Callers share one refresh in
        // flight: a rotating refresh token may be used only once.
        if let refreshing {
            return try unwrap(await refreshing.value)
        }
        let task = Task<Result<ChatGPTCredentials, CredentialSessionError>, Never> {
            do throws(CredentialSessionError) {
                return .success(try await self.refresh(current, hostId: hostId, now: now))
            } catch {
                return .failure(error)
            }
        }
        refreshing = task
        let result = await task.value
        if refreshing == task { refreshing = nil }
        return try unwrap(result)
    }

    private func unwrap(
        _ result: Result<ChatGPTCredentials, CredentialSessionError>
    ) throws(CredentialSessionError) -> ChatGPTCredentials {
        switch result {
        case .success(let credentials): return credentials
        case .failure(let error): throw error
        }
    }

    private func refresh(
        _ current: ChatGPTCredentials,
        hostId: String,
        now: Date
    ) async throws(CredentialSessionError) -> ChatGPTCredentials {
        let response: TokenResponse
        do {
            response = try await tokenClient.refresh(refreshToken: current.refreshToken, clientId: current.clientId)
        } catch let error as OAuthTokenError {
            throw .refreshFailed(code: error.code)
        } catch {
            throw .refreshFailed(code: nil)
        }
        guard !response.accessToken.isEmpty else { throw .refreshIncomplete }
        let scopes = response.scope.map { $0.split(separator: " ").map(String.init) } ?? current.scopes
        let updated = ChatGPTCredentials(
            email: current.email,
            issuer: current.issuer,
            subject: current.subject,
            clientId: current.clientId,
            idToken: response.idToken ?? current.idToken,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? current.refreshToken,
            tokenType: response.tokenType,
            scopes: scopes,
            accessTokenExpiresAt: now.addingTimeInterval(TimeInterval(response.expiresIn)),
            savedAt: now
        )
        do {
            try store.save(CredentialFile(extAgentHostId: hostId, credentials: updated))
        } catch {
            throw .saveFailed
        }
        return updated
    }
}
