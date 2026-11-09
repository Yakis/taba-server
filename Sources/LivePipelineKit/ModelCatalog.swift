import Foundation
import ResponsesKit
import ServerKit

/// The models the signed-in plan offers, kept for an hour. If the list cannot be fetched, the last good list is
/// served, or just the default model when there has never been one. Nothing here logs the access token.
public actor ModelCatalog: TripModelCatalog {
    public nonisolated let defaultModel: String
    static let lifetime: TimeInterval = 3600

    private let fetchSlugs: @Sendable () async throws -> [String]
    private let clock: @Sendable () -> Date
    private var cached: [ModelOption]?
    private var fetchedAt: Date?

    public init(defaultModel: String, clock: @escaping @Sendable () -> Date = { Date() },
                fetchSlugs: @escaping @Sendable () async throws -> [String]) {
        self.defaultModel = defaultModel
        self.clock = clock
        self.fetchSlugs = fetchSlugs
    }

    /// The production catalog: lists the models with the plan's access token.
    public static func live(defaultModel: String, session: CredentialSession, client: ModelsClient) -> ModelCatalog {
        let fetch = ModelsFetch(client: client) { forceRefresh in
            try await session.credentials(forceRefresh: forceRefresh).accessToken
        }
        return ModelCatalog(defaultModel: defaultModel) { try await fetch.slugs() }
    }

    public func options() async -> [ModelOption] {
        if let cached, let fetchedAt, clock().timeIntervalSince(fetchedAt) < Self.lifetime {
            return cached
        }
        do {
            let options = withDefault(ModelChoice.options(fromSlugs: try await fetchSlugs()))
            cached = options
            fetchedAt = clock()
            return options
        } catch {
            return cached ?? [ModelChoice.option(for: defaultModel)]
        }
    }

    /// The default model always appears, first, even when the account's list does not include it. It then takes the
    /// place of its family's entry, so no name appears twice.
    private func withDefault(_ options: [ModelOption]) -> [ModelOption] {
        guard !options.contains(where: { $0.id == defaultModel }) else { return options }
        let option = ModelChoice.option(for: defaultModel)
        return [option] + options.filter { $0.name != option.name }
    }
}

/// Lists the models with the plan's token. If the plan refuses the token, it is refreshed once and the list is
/// asked for again, the same way a stage request is retried.
struct ModelsFetch: Sendable {
    let client: ModelsClient
    let accessToken: @Sendable (_ forceRefresh: Bool) async throws -> String

    func slugs() async throws -> [String] {
        do {
            return try await client.slugs(accessToken: try await accessToken(false))
        } catch ModelsClientError.http(let status) where status == 401 {
            return try await client.slugs(accessToken: try await accessToken(true))
        }
    }
}
