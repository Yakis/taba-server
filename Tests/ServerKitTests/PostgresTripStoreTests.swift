import Foundation
import GuideKit
import Jobs
import JobsPostgres
import Logging
import PipelineKit
import PostgresMigrations
import PostgresNIO
@testable import ServerKit
import Testing

private actor StageCalls {
    private(set) var stages: [BuildStage] = []
    func record(_ stage: BuildStage) { stages.append(stage) }
}

private actor InterruptedStage {
    var started = false
    var cancelled = false
    var outcome: Bool?

    func start() { started = true }
    func cancel() { cancelled = true }
    func finish(safe: Bool) { outcome = safe }
}

private enum FakeFailure: Error { case privateProviderDetail }

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TABA_TEST_POSTGRES"] == "1"))
struct PostgresTripStoreTests {
    private let logger = Logger(label: "postgres-integration-test")

    private func client(database: String) -> PostgresClient {
        PostgresClient(configuration: .init(host: "127.0.0.1", port: 15432,
            username: "taba", password: "taba-local-only", // privacy-scan:allow
            database: database, tls: .disable),
            backgroundLogger: logger)
    }

    // Both clients are run in structured child tasks; the disposable database is intentionally retained.
    @Test(.timeLimit(.minutes(2))) func persistenceAndAdmission() async throws {
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
                try await exercise(postgres)
            }
        }
    }

    // One isolated database covers admission, recovery and real queue processing in sequence.
    // swiftlint:disable:next function_body_length
    private func exercise(_ postgres: PostgresClient) async throws {
        let migrations = DatabaseMigrations()
        await migrations.add(BuildMigration())
        await migrations.add(BuildAttemptMigration())
        let queue = await JobQueue(.postgres(client: postgres, migrations: migrations,
            configuration: .init(queueName: "taba"), logger: logger), logger: logger)
        try await migrations.apply(client: postgres, logger: logger, dryRun: false)
        let store = PostgresTripStore(client: postgres, logger: logger)
        let input = try TripBuildInput(destination: "Edinburgh", from: #require(LocalDate("2025-11-23")),
                                       to: #require(LocalDate("2025-11-25")))
        var trips: [TripStatus] = []
        for _ in 0..<4 { trips.append(try await store.create(input)) }
        #expect(trips.allSatisfy { $0.state == .queued && $0.stage == .basics })
        await #expect(throws: AdmissionError.self) { try await store.create(input) }

        let failure: StageRunner = { _, _ in throw FakeFailure.privateProviderDetail }
        for trip in trips.dropFirst() {
            try await store.process(StageJob(tripID: trip.id, stage: .basics), runner: failure)
            #expect(try await store.status(trip.id)?.state == .failed)
            let events = try await store.events(trip.id, after: 0)
            #expect(events.last?.status.state == .failed)
            let publicData = try JSONEncoder().encode(events)
            let publicJSON = try #require(String(data: publicData, encoding: .utf8))
            #expect(!publicJSON.contains("privateProviderDetail"))
        }
        let id = try #require(trips.first?.id)
        let guideURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Data(contentsOf: guideURL))
        let calls = StageCalls()
        let runner: StageRunner = { work, evidence in
            await calls.record(work.stage)
            let previous = Array(BuildStage.allCases.prefix { $0 != work.stage })
            #expect(Set(work.checkpoints.keys) == Set(previous))
            for stage in previous { #expect(work.checkpoints[stage] == Data(stage.rawValue.utf8)) }
            if work.stage == .write {
                await evidence(.pipeline(.copy(issues: [.init(kind: .ungroundedNumber("42"),
                    path: "hero.title", text: "A 42 example")])))
            }
            return StageResult(checkpoint: Data(work.stage.rawValue.utf8),
                               guide: work.stage == .assemble ? guide : nil)
        }
        for stage in BuildStage.allCases {
            // A fresh store sees the committed checkpoint and the successor outbox.
            let resumed = PostgresTripStore(client: postgres, logger: logger)
            let before = try #require(try await resumed.status(id))
            #expect(before.stage == stage)
            #expect(before.state == .queued)
            try await resumed.dispatch(queue: queue)
            let dispatched = try await postgres.query(
                "SELECT dispatched_at IS NOT NULL FROM taba_trips WHERE id = \(id)", logger: logger)
            var marked = false
            for try await value in dispatched.decode(Bool.self) { marked = value }
            #expect(marked)
            try await resumed.process(StageJob(tripID: id, stage: stage), runner: runner)
            if stage.next != nil {
                let outbox = try await postgres.query(
                    "SELECT dispatched_at IS NULL FROM taba_trips WHERE id = \(id)", logger: logger)
                var pending = false
                for try await value in outbox.decode(Bool.self) { pending = value }
                #expect(pending)
            }
            try await resumed.process(StageJob(tripID: id, stage: stage), runner: runner)
        }
        #expect(await calls.stages == BuildStage.allCases)
        let finished = try #require(try await store.status(id))
        #expect(finished.state == .completed)
        #expect(finished.copyReviewRequired)
        #expect(try await store.guide(id)?.id == guide.id)
        let flags = try await store.reviews(id)
        #expect(flags.count == 1)
        #expect(flags.first?.path == "hero.title")
        #expect(flags.first?.text == "A 42 example")
        let events = try await store.events(id, after: 0)
        #expect(events.last?.status.state == .completed)
        #expect(events.last?.status.copyReviewRequired == true)
        let first = try #require(events.first)
        #expect(try await store.events(id, after: first.id).count == events.count - 1)
        // Exercise the actual dispatcher and queue processor, not just direct process calls.
        queue.registerJob(JobDefinition(parameters: StageJob.self, retryStrategy: .dontRetry) { job, _ in
            try await store.process(job, runner: runner)
        })
        let queued = try await store.create(input) // terminal builds release admission capacity
        try await withThrowingTaskGroup(of: Void.self) { services in
            services.addTask { try await queue.processor(options: .init(numWorkers: 1)).run() }
            services.addTask { try await BuildDispatcher(store: store, queue: queue, migrations: migrations).run() }
            defer { services.cancelAll() }
            for _ in 0..<200 {
                if try await store.status(queued.id)?.state.isTerminal == true { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(try await store.status(queued.id)?.state == .completed)
            #expect(try await store.guide(queued.id)?.id == guide.id)
        }
        try await connectionLoss(postgres, store: store, input: input)
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func connectionLoss(_ postgres: PostgresClient, store: PostgresTripStore,
                                input: TripBuildInput) async throws {
        let trip = try await store.create(input)
        let job = StageJob(tripID: trip.id, stage: .basics)
        let signal = InterruptedStage()
        let blocked: StageRunner = { _, _ in
            await signal.start()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                await signal.cancel()
                throw error
            }
            return StageResult(checkpoint: Data("interrupted".utf8), guide: nil)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    try await store.process(job, runner: blocked)
                    await signal.finish(safe: false)
                } catch BuildStoreError.interrupted {
                    await signal.finish(safe: true)
                } catch {
                    await signal.finish(safe: false)
                }
            }
            defer { group.cancelAll() }
            for _ in 0..<100 {
                if await signal.started { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(await signal.started)
            let attemptRows = try await postgres.query(
                "SELECT attempt_id FROM taba_trips WHERE id = \(trip.id)", logger: logger)
            var oldAttempt: UUID?
            for try await value in attemptRows.decode(UUID?.self) { oldAttempt = value }
            let oldID = try #require(oldAttempt)
            // Restrict termination to the unique advisory-lock holder in this disposable database.
            let locks = try await postgres.query("""
                SELECT pid FROM pg_locks WHERE locktype = 'advisory' AND granted
                AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
                AND classid = 0 AND objid = 8417301 AND objsubid = 1
                """, logger: logger)
            var pids: [Int32] = []
            for try await pid in locks.decode(Int32.self) { pids.append(pid) }
            #expect(pids.count == 1)
            let pid = try #require(pids.count == 1 ? pids.first : nil)
            let killed = try await postgres.query("SELECT pg_terminate_backend(\(pid))", logger: logger)
            var terminated = false
            for try await value in killed.decode(Bool.self) { terminated = value }
            try #require(terminated)
            for _ in 0..<100 {
                if await signal.outcome != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(await signal.cancelled)
            try #require(await signal.outcome == true)
            let checkpoints = try await postgres.query(
                "SELECT count(*) FROM taba_checkpoints WHERE trip_id = \(trip.id)", logger: logger)
            for try await count in checkpoints.decode(Int64.self) { #expect(count == 0) }
            let before = try await postgres.query(
                "SELECT count(*) FROM taba_evidence WHERE trip_id = \(trip.id)", logger: logger)
            var evidenceCount: Int64 = -1
            for try await count in before.decode(Int64.self) { evidenceCount = count }
            let calls = StageCalls()
            let resumed = PostgresTripStore(client: postgres, logger: logger)
            let recovery: StageRunner = { work, _ in
                await calls.record(work.stage)
                #expect(work.checkpoints.isEmpty)
                let rows = try await postgres.query(
                    "SELECT attempt_id FROM taba_trips WHERE id = \(trip.id)", logger: logger)
                var current: UUID?
                for try await value in rows.decode(UUID?.self) { current = value }
                #expect(current != nil && current != oldID)
                await #expect(throws: BuildStoreError.self) {
                    try await resumed.append(.pipeline(.copy(issues: [.init(kind: .ungroundedNumber("42"),
                        path: "hero.title", text: "A 42 example")])), tripID: trip.id,
                                             stage: .basics, attemptID: oldID)
                }
                return StageResult(checkpoint: Data("recovered".utf8), guide: nil)
            }
            try await resumed.process(job, runner: recovery)
            #expect(await calls.stages == [.basics])
            #expect(try await resumed.status(trip.id)?.stage == BuildStage.basics.next)
            #expect(try await resumed.status(trip.id)?.copyReviewRequired == false)
            #expect(try await resumed.reviews(trip.id).isEmpty)
            let after = try await postgres.query(
                "SELECT count(*) FROM taba_evidence WHERE trip_id = \(trip.id)", logger: logger)
            for try await count in after.decode(Int64.self) { #expect(count == evidenceCount) }
            let saved = try await postgres.query(
                "SELECT payload FROM taba_checkpoints WHERE trip_id = \(trip.id)", logger: logger)
            var payloads: [Data] = []
            for try await payload in saved.decode(Data.self) { payloads.append(payload) }
            #expect(payloads == [Data("recovered".utf8)])
        }
    }
}
