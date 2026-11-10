import Foundation
import GuideKit
import Jobs
import JobsPostgres
import Logging
import PostgresMigrations
import PostgresNIO
@testable import ServerKit
import Testing

private actor StageOverlap {
    private var active = 0
    private(set) var maximum = 0

    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() { active -= 1 }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TABA_TEST_POSTGRES"] == "1"))
struct PostgresStageParallelismTests {
    private let logger = Logger(label: "postgres-integration-test")

    @Test(.timeLimit(.minutes(2))) func stagesOfDifferentTripsRunAtTheSameTime() async throws {
        try await PostgresTestDatabase.withIsolatedDatabase { postgres in
            let store = try await migratedStore(postgres)
            let input = try TripBuildInput(destination: "Edinburgh", from: #require(LocalDate("2025-11-23")),
                                           to: #require(LocalDate("2025-11-25")))
            let first = try await store.create(input, model: "gpt-6.1-sol")
            let second = try await store.create(input, model: "gpt-6.1-sol")
            let overlap = StageOverlap()
            let runner: StageRunner = { _, _ in
                await overlap.enter()
                try await Task.sleep(for: .milliseconds(500))
                await overlap.leave()
                return StageResult(checkpoint: Data("basics".utf8))
            }
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await store.process(StageJob(tripID: first.id, stage: .basics), runner: runner) }
                group.addTask { try await store.process(StageJob(tripID: second.id, stage: .basics), runner: runner) }
                try await group.waitForAll()
            }
            #expect(await overlap.maximum == 2)
            for trip in [first, second] {
                #expect(try await store.status(trip.id)?.stage == BuildStage.basics.next)
            }
        }
    }

    @Test(.timeLimit(.minutes(2))) func aDuplicateJobWhileItsStageRunsDoesNothing() async throws {
        try await PostgresTestDatabase.withIsolatedDatabase { postgres in
            let store = try await migratedStore(postgres)
            let input = try TripBuildInput(destination: "Edinburgh", from: #require(LocalDate("2025-11-23")),
                                           to: #require(LocalDate("2025-11-25")))
            let trip = try await store.create(input, model: "gpt-6.1-sol")
            let job = StageJob(tripID: trip.id, stage: .basics)
            let calls = StageCalls()
            let runner: StageRunner = { work, _ in
                await calls.record(work.stage)
                try await Task.sleep(for: .milliseconds(800))
                return StageResult(checkpoint: Data("basics".utf8))
            }
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await store.process(job, runner: runner) }
                try await Task.sleep(for: .milliseconds(200))
                // Arrives while the first attempt holds the trip's lock: it waits, then finds the stage moved on.
                group.addTask { try await store.process(job, runner: runner) }
                try await group.waitForAll()
            }
            #expect(await calls.stages == [.basics])
            #expect(try await store.status(trip.id)?.stage == BuildStage.basics.next)
        }
    }

    private func migratedStore(_ postgres: PostgresClient) async throws -> PostgresTripStore {
        let migrations = DatabaseMigrations()
        await migrations.add(BuildMigration())
        await migrations.add(BuildAttemptMigration())
        await migrations.add(BuildModelMigration())
        try await migrations.apply(client: postgres, logger: logger, dryRun: false)
        return PostgresTripStore(client: postgres, logger: logger)
    }

}
