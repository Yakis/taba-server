import Foundation
import PostgresNIO

extension PostgresTripStore {
    /// Deletes a finished trip and every row stored for it, in one transaction. The trip row is locked
    /// first, so a build cannot start or record evidence while its rows are being removed.
    public func delete(_ id: UUID) async throws -> TripDeletion {
        try await client.withTransaction(logger: logger) { connection -> TripDeletion in
            let rows = try await connection.query("""
                SELECT state FROM taba_trips WHERE id = \(id) FOR UPDATE
                """, logger: logger)
            var state: String?
            for try await value in rows.decode(String.self) { state = value }
            guard let state else { return .notFound }
            guard !["queued", "running"].contains(state) else { return .stillBuilding }
            try await connection.query("DELETE FROM taba_progress WHERE trip_id = \(id)", logger: logger)
            try await connection.query("DELETE FROM taba_evidence WHERE trip_id = \(id)", logger: logger)
            try await connection.query("DELETE FROM taba_checkpoints WHERE trip_id = \(id)", logger: logger)
            try await connection.query("DELETE FROM taba_copy_reviews WHERE trip_id = \(id)", logger: logger)
            try await connection.query("DELETE FROM taba_trips WHERE id = \(id)", logger: logger)
            return .deleted
        }
    }
}
