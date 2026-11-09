import Logging
import PostgresMigrations
import PostgresNIO

/// Private inputs/evidence are bytes, not JSON query parameters or log metadata.
public struct BuildMigration: DatabaseMigration {
    public init() {}

    public func apply(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query("""
            CREATE TABLE taba_trips (
                id UUID PRIMARY KEY, input BYTEA NOT NULL, state TEXT NOT NULL,
                stage TEXT NOT NULL, review BOOLEAN NOT NULL DEFAULT FALSE, guide BYTEA,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now(), dispatched_at TIMESTAMPTZ,
                attempts INTEGER NOT NULL DEFAULT 0
            )
            """, logger: logger)
        try await connection.query("""
            CREATE TABLE taba_checkpoints (
                trip_id UUID NOT NULL REFERENCES taba_trips(id), stage TEXT NOT NULL,
                payload BYTEA NOT NULL, PRIMARY KEY(trip_id, stage)
            )
            """, logger: logger)
        try await connection.query("""
            CREATE TABLE taba_progress (
                id BIGSERIAL PRIMARY KEY, trip_id UUID NOT NULL REFERENCES taba_trips(id),
                state TEXT NOT NULL, stage TEXT NOT NULL, review BOOLEAN NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """, logger: logger)
        try await connection.query("""
            CREATE INDEX taba_progress_trip ON taba_progress(trip_id, id)
            """, logger: logger)
        try await connection.query("""
            CREATE TABLE taba_evidence (
                id BIGSERIAL PRIMARY KEY, trip_id UUID NOT NULL REFERENCES taba_trips(id),
                stage TEXT NOT NULL, payload BYTEA NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """, logger: logger)
        try await connection.query("""
            CREATE TABLE taba_copy_reviews (
                id BIGSERIAL PRIMARY KEY, trip_id UUID NOT NULL REFERENCES taba_trips(id), payload BYTEA NOT NULL
            )
            """, logger: logger)
    }

    public func revert(connection: PostgresConnection, logger: Logger) async throws {
        try await connection.query("DROP TABLE taba_copy_reviews", logger: logger)
        try await connection.query("DROP TABLE taba_evidence", logger: logger)
        try await connection.query("DROP TABLE taba_progress", logger: logger)
        try await connection.query("DROP TABLE taba_checkpoints", logger: logger)
        try await connection.query("DROP TABLE taba_trips", logger: logger)
    }
}
