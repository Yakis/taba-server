import Foundation
import GuideKit
import PostgresNIO

/// The lock and build-time steps of a stage, kept out of `PostgresTripStore` itself.
extension PostgresTripStore {
    func tryStageLock(_ connection: PostgresConnection, tripID: UUID) async throws -> Bool {
        let rows = try await connection.query("""
            SELECT pg_try_advisory_lock(\(Self.stageLockClass), hashtext(\(tripID)::uuid::text))
            """, logger: logger)
        for try await acquired in rows.decode(Bool.self) { return acquired }
        return false
    }

    func unlock(_ connection: PostgresConnection, tripID: UUID) async throws {
        try await connection.query("""
            SELECT pg_advisory_unlock(\(Self.stageLockClass), hashtext(\(tripID)::uuid::text))
            """, logger: logger)
    }

    /// Transactional, so it is released at the end of the dispatcher's transaction.
    func tryDispatchLock(_ connection: PostgresConnection) async throws -> Bool {
        let rows = try await connection.query("SELECT pg_try_advisory_xact_lock(\(Self.dispatchLock))", logger: logger)
        for try await acquired in rows.decode(Bool.self) { return acquired }
        return false
    }

    /// How long the build took. `created_at` and the progress rows are read with the database clock, so the total
    /// and the work time share one `now()`.
    func buildTime(tripID: UUID, connection: PostgresConnection) async throws -> BuildTime {
        let trips = try await connection.query("""
            SELECT created_at, now() FROM taba_trips WHERE id = \(tripID)
            """, logger: logger)
        var created: Date?
        var now: Date?
        for try await (start, current) in trips.decode((Date, Date).self) {
            created = start
            now = current
        }
        let progress = try await connection.query("""
            SELECT state, created_at FROM taba_progress WHERE trip_id = \(tripID) ORDER BY id
            """, logger: logger)
        var events: [BuildTiming.Event] = []
        for try await (state, enteredAt) in progress.decode((String, Date).self) {
            guard let state = TripState(rawValue: state) else { throw BuildStoreError.corruptCheckpoint }
            events.append(BuildTiming.Event(state: state, enteredAt: enteredAt))
        }
        guard let created, let now else { throw BuildStoreError.corruptCheckpoint }
        return BuildTiming.buildTime(created: created, events: events, now: now)
    }
}
