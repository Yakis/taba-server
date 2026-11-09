import Logging
import PostgresMigrations
import PostgresNIO

/// A fencing token prevents an interrupted attempt from recording evidence after recovery.
public struct BuildAttemptMigration: DatabaseMigration {
    public init() {}

    public func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query("ALTER TABLE taba_trips ADD COLUMN attempt_id UUID", logger: logger)
    }

    public func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query("ALTER TABLE taba_trips DROP COLUMN attempt_id", logger: logger)
    }
}
