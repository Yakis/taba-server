import Foundation
import GuideKit
import Logging
import PipelineKit
import PostgresMigrations
import PostgresNIO
@testable import ServerKit
import Testing

private struct StoredRows: Equatable {
    let progress: Int64
    let evidence: Int64
    let checkpoints: Int64
    let reviews: Int64
    let trips: Int64

    static let none = StoredRows(progress: 0, evidence: 0, checkpoints: 0, reviews: 0, trips: 0)
}

private enum DeletionFailure: Error { case providerDetail }

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TABA_TEST_POSTGRES"] == "1"))
struct PostgresTripDeletionTests {
    private let logger = Logger(label: "postgres-integration-test")

    @Test(.timeLimit(.minutes(2))) func deletingFinishedTrips() async throws {
        try await PostgresTestDatabase.withIsolatedDatabase { postgres in try await deletion(postgres) }
    }

    private func storedRows(_ postgres: PostgresClient, trip id: UUID) async throws -> StoredRows {
        let rows = try await postgres.query("""
            SELECT (SELECT count(*) FROM taba_progress WHERE trip_id = \(id)),
                   (SELECT count(*) FROM taba_evidence WHERE trip_id = \(id)),
                   (SELECT count(*) FROM taba_checkpoints WHERE trip_id = \(id)),
                   (SELECT count(*) FROM taba_copy_reviews WHERE trip_id = \(id)),
                   (SELECT count(*) FROM taba_trips WHERE id = \(id))
            """, logger: logger)
        var result: StoredRows?
        for try await (progress, evidence, checkpoints, reviews, trips)
            in rows.decode((Int64, Int64, Int64, Int64, Int64).self) {
            result = StoredRows(progress: progress, evidence: evidence, checkpoints: checkpoints,
                                reviews: reviews, trips: trips)
        }
        return try #require(result)
    }

    // Deletion removes finished trips and every row for them. A queued or running trip is refused, and a
    // job that outlives its deleted trip runs nothing and writes nothing.
    private func deletion(_ postgres: PostgresClient) async throws {
        let migrations = DatabaseMigrations()
        await migrations.add(BuildMigration())
        await migrations.add(BuildAttemptMigration())
        await migrations.add(BuildModelMigration())
        try await migrations.apply(client: postgres, logger: logger, dryRun: false)
        let store = PostgresTripStore(client: postgres, logger: logger)
        let input = try TripBuildInput(destination: "Edinburgh", from: #require(LocalDate("2025-11-23")),
                                       to: #require(LocalDate("2025-11-25")))
        let guide = try PostgresTestDatabase.fixtureGuide()
        let runner: StageRunner = { work, evidence in
            if work.stage == .write {
                await evidence(.pipeline(.copy(issues: [.init(kind: .ungroundedNumber("42"),
                    path: "hero.title", text: "A 42 example")])))
            }
            return StageResult(checkpoint: Data(work.stage.rawValue.utf8),
                               guide: work.stage == .assemble ? guide : nil)
        }

        // A finished build fills every child table: progress, evidence, checkpoints and a copy review.
        let finished = try await store.create(input, model: "gpt-6.1-sol")
        for stage in BuildStage.allCases {
            try await store.process(StageJob(tripID: finished.id, stage: stage), runner: runner)
        }
        #expect(try await store.status(finished.id)?.state == .completed)
        let filled = try await storedRows(postgres, trip: finished.id)
        #expect(filled.progress > 0 && filled.evidence > 0 && filled.checkpoints > 0)
        #expect(filled.reviews == 1 && filled.trips == 1)

        // A queued trip, and a trip marked running, are refused and keep every row.
        let building = try await store.create(input, model: "gpt-6.1-sol")
        let queuedRows = try await storedRows(postgres, trip: building.id)
        #expect(try await store.delete(building.id) == .stillBuilding)
        try await postgres.query("UPDATE taba_trips SET state = 'running' WHERE id = \(building.id)", logger: logger)
        #expect(try await store.delete(building.id) == .stillBuilding)
        #expect(try await store.status(building.id)?.state == .running)
        #expect(try await storedRows(postgres, trip: building.id) == queuedRows)

        #expect(try await store.delete(UUID()) == .notFound)
        #expect(try await store.delete(finished.id) == .deleted)
        #expect(try await store.status(finished.id) == nil)
        #expect(try await store.guide(finished.id) == nil)
        #expect(try await store.events(finished.id, after: 0).isEmpty)
        #expect(try await storedRows(postgres, trip: finished.id) == StoredRows.none)
        #expect(try await store.delete(finished.id) == .notFound)

        // A failed trip can be deleted, and a stale job for it runs no stage and writes nothing.
        let failed = try await store.create(input, model: "gpt-6.1-sol")
        let failure: StageRunner = { _, _ in throw DeletionFailure.providerDetail }
        try await store.process(StageJob(tripID: failed.id, stage: .basics), runner: failure)
        #expect(try await store.status(failed.id)?.state == .failed)
        #expect(try await store.delete(failed.id) == .deleted)
        try await store.process(StageJob(tripID: failed.id, stage: .basics), runner: { _, _ in
            Issue.record("A stage ran for a deleted trip")
            return StageResult(checkpoint: Data("stale".utf8))
        })
        #expect(try await storedRows(postgres, trip: failed.id) == StoredRows.none)
    }
}
