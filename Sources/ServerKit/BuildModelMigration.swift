import Logging
import PostgresMigrations
import PostgresNIO

/// Records the AI model each trip is built with. Trips admitted before this migration have no model.
public struct BuildModelMigration: DatabaseMigration {
    public init() {}

    public func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query("ALTER TABLE taba_trips ADD COLUMN model TEXT", logger: logger)
    }

    public func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query("ALTER TABLE taba_trips DROP COLUMN model", logger: logger)
    }
}
