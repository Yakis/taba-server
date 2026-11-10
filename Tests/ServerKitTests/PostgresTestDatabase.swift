import Foundation
import GuideKit
import Logging
import PostgresNIO
import Testing

/// Shared setup for the Postgres integration tests, which run only with TABA_TEST_POSTGRES=1.
enum PostgresTestDatabase {
    static let logger = Logger(label: "postgres-integration-test")

    static func client(database: String) -> PostgresClient {
        PostgresClient(configuration: .init(host: "127.0.0.1", port: 15432,
            username: "taba", password: "taba-local-only", // privacy-scan:allow
            database: database, tls: .disable),
            backgroundLogger: logger)
    }

    // Both clients are run in structured child tasks; the disposable database is intentionally retained.
    static func withIsolatedDatabase(_ body: (PostgresClient) async throws -> Void) async throws {
        let admin = client(database: "taba")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await admin.run() }
            defer { group.cancelAll() }
            let database = "taba_test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            // Identifier is generated exclusively from a UUID, not user input.
            do {
                try await admin.query(PostgresQuery(unsafeSQL: "CREATE DATABASE \(database)"), logger: logger)
            } catch let error as PSQLError {
                let code = error.serverInfo?[.sqlState] ?? "unavailable"
                Issue.record("Creating isolated database failed; SQLSTATE: \(code)")
                throw error
            }
            let postgres = client(database: database)
            try await withThrowingTaskGroup(of: Void.self) { inner in
                inner.addTask { await postgres.run() }
                defer { inner.cancelAll() }
                try await body(postgres)
            }
        }
    }

    static func fixtureGuide() throws -> Guide {
        let guideURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        return try GuideKit.jsonDecoder().decode(Guide.self, from: Data(contentsOf: guideURL))
    }
}
