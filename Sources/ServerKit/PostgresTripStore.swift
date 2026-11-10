import Foundation
import GuideKit
import Jobs
import JobsPostgres
import Logging
import PipelineKit
import PostgresNIO

public enum BuildStoreError: Error { case corruptCheckpoint, evidenceFailed, invalidResult, interrupted }

/// Stages run in parallel across trips, one at a time per trip. Each stage holds a session advisory lock keyed by
/// its trip, `pg_try_advisory_lock(stageLockClass, hashtext(trip id))`, on a dedicated pooled connection for the
/// whole stage, so a process crash releases it automatically. Two jobs for the same trip never run together, so a
/// duplicate delivery is harmless. Dispatch takes its own transactional lock (`dispatchLock`), so one dispatcher
/// pushes at a time without waiting for running stages. The trips row is also a durable outbox: advancing a
/// checkpoint makes its successor dispatchable.
public struct PostgresTripStore: TripHTTPStore, Sendable {
    public let client: PostgresClient
    public let logger: Logger
    /// The class key of the per-trip stage locks (the two-key form of `pg_advisory_lock`).
    static let stageLockClass: Int32 = 8_417
    static let dispatchLock: Int64 = 8_417_303
    static let admissionLock: Int64 = 8_417_302

    public init(client: PostgresClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    public func create(_ input: TripBuildInput, model: String) async throws -> TripStatus {
        let id = UUID()
        let payload = try JSONEncoder().encode(input)
        let admitted: TripStatus? = try await client.withTransaction(logger: logger) { connection in
            try await connection.query("SELECT pg_advisory_xact_lock(\(Self.admissionLock))", logger: logger)
            let rows = try await connection.query("""
                SELECT count(*) FROM taba_trips WHERE state IN ('queued', 'running')
                """, logger: logger)
            for try await count in rows.decode(Int64.self) where count >= 4 { return nil }
            try await connection.query("""
                INSERT INTO taba_trips (id, input, state, stage, model)
                VALUES (\(id), \(payload), 'queued', 'basics', \(model))
                """, logger: logger)
            let status = TripStatus(id: id, state: .queued, stage: .basics, model: model)
            try await progress(status, connection: connection)
            return status
        }
        guard let admitted else { throw AdmissionError.full }
        return admitted
    }

    public func status(_ id: UUID) async throws -> TripStatus? {
        let rows = try await client.query(
            "SELECT state, stage, review, model FROM taba_trips WHERE id = \(id)", logger: logger)
        for try await (state, stage, review, model) in rows.decode((String, String, Bool, String?).self) {
            return try Self.status(id, state: state, stage: stage, review: review, model: model)
        }
        return nil
    }

    public func guide(_ id: UUID) async throws -> Guide? {
        let rows = try await client.query("""
            SELECT guide FROM taba_trips WHERE id = \(id) AND state = 'completed'
            """, logger: logger)
        for try await data in rows.decode(Data.self) { return try JSONDecoder().decode(Guide.self, from: data) }
        return nil
    }

    public func events(_ id: UUID, after: Int64) async throws -> [ProgressEvent] {
        let rows = try await client.query("""
            SELECT p.id, p.state, p.stage, p.review, t.model FROM taba_progress p
            JOIN taba_trips t ON t.id = p.trip_id
            WHERE p.trip_id = \(id) AND p.id > \(after) ORDER BY p.id LIMIT 100
            """, logger: logger)
        var result: [ProgressEvent] = []
        let decoded = rows.decode((Int64, String, String, Bool, String?).self)
        for try await (eventID, state, stage, review, model) in decoded {
            result.append(ProgressEvent(id: eventID,
                status: try Self.status(id, state: state, stage: stage, review: review, model: model)))
        }
        return result
    }

    /// Dispatch is at least once: a crash between push and dispatched_at may duplicate the job.
    /// Processing checks the current stage under the trip's stage lock, so duplicate delivery is harmless.
    /// A trip whose stage has run for more than 30 seconds is pushed again each time; that duplicate waits for the
    /// trip's lock, finds it held, and does nothing.
    public func dispatch(queue: JobQueue<PostgresJobQueue>) async throws {
        try await client.withTransaction(logger: logger) { connection in
            guard try await tryDispatchLock(connection) else { return }
            let rows = try await connection.query("""
                SELECT id, stage FROM taba_trips WHERE state IN ('queued', 'running')
                AND (dispatched_at IS NULL OR dispatched_at < now() - INTERVAL '30 seconds')
                ORDER BY created_at LIMIT 4 FOR UPDATE
                """, logger: logger)
            for try await (id, rawStage) in rows.decode((UUID, String).self) {
                guard let stage = BuildStage(rawValue: rawStage) else { throw BuildStoreError.corruptCheckpoint }
                try await queue.push(StageJob(tripID: id, stage: stage))
                try await connection.query("""
                    UPDATE taba_trips SET dispatched_at = now() WHERE id = \(id)
                    """, logger: logger)
            }
        }
    }

    /// No automatic retry on ordinary provider/validation failures. A process death may repeat only
    /// its in-flight stage, never an already committed stage. Three interrupted attempts is the cap.
    public func process(_ job: StageJob, runner: @escaping StageRunner) async throws {
        try await client.withConnection { connection in
            guard try await waitForLock(connection, tripID: job.tripID) else { return }
            do {
                try await processLocked(job, connection: connection, runner: runner)
                guard !connection.isClosed else { throw BuildStoreError.interrupted }
                try await unlock(connection, tripID: job.tripID)
            } catch {
                // Never query an already closed connection or return a held session lock to the pool.
                if !connection.isClosed {
                    do {
                        try await unlock(connection, tripID: job.tripID)
                    } catch { try? await connection.close() }
                }
                throw BuildStoreError.interrupted
            }
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func processLocked(_ job: StageJob, connection: PostgresConnection,
                               runner: @escaping StageRunner) async throws {
        let rows = try await connection.query("""
            SELECT input, state, stage, attempts FROM taba_trips WHERE id = \(job.tripID)
            """, logger: logger)
        var input: TripBuildInput?
        var attempts = 0
        for try await (payload, state, stage, count) in rows.decode((Data, String, String, Int).self) {
            guard ["queued", "running"].contains(state), stage == job.stage.rawValue else { return }
            input = try JSONDecoder().decode(TripBuildInput.self, from: payload)
            attempts = count
        }
        guard let input else { return }
        guard attempts < 3 else {
            try await fail(job, connection: connection)
            return
        }
        let checkpointRows = try await connection.query("""
            SELECT stage, payload FROM taba_checkpoints WHERE trip_id = \(job.tripID)
            """, logger: logger)
        var checkpoints: [BuildStage: Data] = [:]
        for try await (stage, data) in checkpointRows.decode((String, Data).self) {
            guard let stage = BuildStage(rawValue: stage) else { throw BuildStoreError.corruptCheckpoint }
            checkpoints[stage] = data
        }
        let attemptID = UUID()
        // A trip deleted (or moved on) since the check above makes this job a quiet no-op.
        guard try await claim(job, attemptID: attemptID, connection: connection) else { return }
        let recorder = DurableEvidence(store: self, tripID: job.tripID, stage: job.stage, attemptID: attemptID)
        let work = BuildWork(tripID: job.tripID, input: input, stage: job.stage, checkpoints: checkpoints)
        let result: StageResult
        do {
            result = try await monitoredRun(work, connection: connection, runner: runner, recorder: recorder)
            try Task.checkCancellation()
            try await recorder.check()
            guard result.checkpoint.count <= 32 * 1024 * 1024,
                  (job.stage == .assemble) == (result.guide != nil) else { throw BuildStoreError.invalidResult }
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            guard !connection.isClosed else { throw BuildStoreError.interrupted }
            try await fail(job, connection: connection)
            return
        }
        try await connection.withTransaction(logger: logger) { connection in
            try await connection.query("""
                INSERT INTO taba_checkpoints (trip_id, stage, payload)
                VALUES (\(job.tripID), \(job.stage.rawValue), \(result.checkpoint))
                """, logger: logger)
            var guide: Data?
            if let finished = result.guide {
                // Read before this transaction writes its own progress row: the build ends with this row.
                let time = try await buildTime(tripID: job.tripID, connection: connection)
                guide = try JSONEncoder().encode(finished.recordingBuildTime(time))
            }
            let stage = job.stage.next ?? job.stage
            let state: TripState = job.stage.next == nil ? .completed : .queued
            try await connection.query("""
                UPDATE taba_trips SET state = \(state.rawValue), stage = \(stage.rawValue), guide = \(guide),
                dispatched_at = NULL, attempts = 0 WHERE id = \(job.tripID)
                """, logger: logger)
            // This update atomically creates the successor's durable outbox entry.
            let review = try await hasReview(job.tripID, connection: connection)
            try await progress(TripStatus(id: job.tripID, state: state, stage: stage,
                                          copyReviewRequired: review), connection: connection)
        }
    }

    /// Marks the trip running for this attempt. The conditional update locks the trip row, so a delete cannot
    /// commit between the caller's check and this claim. False means the trip is gone or has already moved on.
    private func claim(_ job: StageJob, attemptID: UUID, connection: PostgresConnection) async throws -> Bool {
        try await connection.withTransaction(logger: logger) { connection -> Bool in
            let rows = try await connection.query("""
                UPDATE taba_trips SET state = 'running', attempts = attempts + 1, attempt_id = \(attemptID)
                WHERE id = \(job.tripID) AND state IN ('queued', 'running') AND stage = \(job.stage.rawValue)
                RETURNING id
                """, logger: logger)
            var claimed = false
            for try await _ in rows.decode(UUID.self) { claimed = true }
            guard claimed else { return false }
            try await progress(TripStatus(id: job.tripID, state: .running, stage: job.stage), connection: connection)
            return true
        }
    }

    private func monitoredRun(_ work: BuildWork, connection: PostgresConnection,
                              runner: @escaping StageRunner, recorder: DurableEvidence) async throws -> StageResult {
        try await withThrowingTaskGroup(of: StageResult.self) { tasks in
            tasks.addTask { try await runner(work, { await recorder.append($0) }) }
            tasks.addTask {
                while true {
                    try await Task.sleep(for: .milliseconds(200))
                    // Do not query a closed PostgresNIO connection: its query future can remain pending.
                    // Channel closure releases the session lock; cancel provider work within one tick.
                    guard !connection.isClosed else { throw BuildStoreError.interrupted }
                }
            }
            defer { tasks.cancelAll() }
            guard let result = try await tasks.next() else { throw BuildStoreError.interrupted }
            return result
        }
    }

    func append(_ event: BuildEvidence, tripID: UUID, stage: BuildStage, attemptID: UUID) async throws {
        let data = try JSONEncoder().encode(EvidenceRecord(event))
        let accepted = try await client.withTransaction(logger: logger) { connection in
            let rows = try await connection.query("""
                SELECT attempt_id, state FROM taba_trips WHERE id = \(tripID) FOR UPDATE
                """, logger: logger)
            var current = false
            for try await (token, state) in rows.decode((UUID?, String).self) {
                current = token == attemptID && state == "running"
            }
            guard current else { return false }
            try await connection.query("""
                INSERT INTO taba_evidence (trip_id, stage, payload) VALUES (\(tripID), \(stage.rawValue), \(data))
                """, logger: logger)
            if case .pipeline(.copy(let issues)) = event, !issues.isEmpty {
                let flags = try JSONEncoder().encode(issues.map(CopyReviewFlag.init))
                try await connection.query("""
                    INSERT INTO taba_copy_reviews (trip_id, payload) VALUES (\(tripID), \(flags))
                    """, logger: logger)
                try await connection.query(
                    "UPDATE taba_trips SET review = TRUE WHERE id = \(tripID)", logger: logger)
            }
            return true
        }
        guard accepted else { throw BuildStoreError.interrupted }
    }

    private func fail(_ job: StageJob, connection: PostgresConnection) async throws {
        try await connection.withTransaction(logger: logger) { connection in
            try await connection.query(
                "UPDATE taba_trips SET state = 'failed' WHERE id = \(job.tripID)", logger: logger)
            let review = try await hasReview(job.tripID, connection: connection)
            try await progress(TripStatus(id: job.tripID, state: .failed, stage: job.stage,
                                          copyReviewRequired: review), connection: connection)
        }
    }

    private func hasReview(_ id: UUID, connection: PostgresConnection) async throws -> Bool {
        let rows = try await connection.query("SELECT review FROM taba_trips WHERE id = \(id)", logger: logger)
        for try await value in rows.decode(Bool.self) { return value }
        return false
    }

    /// The same trip's previous stage still holds its lock for a moment after it commits, because the unlock comes
    /// after the commit, and a successor job can arrive in that moment. So wait up to two seconds instead of dropping
    /// the job and stalling the trip until redelivery. A stage of this trip running elsewhere still makes this
    /// return false, and then the job does nothing.
    private func waitForLock(_ connection: PostgresConnection, tripID: UUID) async throws -> Bool {
        for attempt in 0..<20 {
            if try await tryStageLock(connection, tripID: tripID) { return true }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(100)) }
        }
        return false
    }

    private func progress(_ status: TripStatus, connection: PostgresConnection) async throws {
        try await connection.query("""
            INSERT INTO taba_progress (trip_id, state, stage, review)
            VALUES (\(status.id), \(status.state.rawValue), \(status.stage.rawValue), \(status.copyReviewRequired))
            """, logger: logger)
    }

    private static func status(_ id: UUID, state: String, stage: String, review: Bool,
                               model: String?) throws -> TripStatus {
        guard let state = TripState(rawValue: state), let stage = BuildStage(rawValue: stage) else {
            throw BuildStoreError.corruptCheckpoint
        }
        return TripStatus(id: id, state: state, stage: stage, copyReviewRequired: review, model: model)
    }
}

private actor DurableEvidence {
    let store: PostgresTripStore
    let tripID: UUID
    let stage: BuildStage
    let attemptID: UUID
    var failed = false

    init(store: PostgresTripStore, tripID: UUID, stage: BuildStage, attemptID: UUID) {
        self.store = store; self.tripID = tripID; self.stage = stage; self.attemptID = attemptID
    }

    func append(_ event: BuildEvidence) async {
        do {
            try await store.append(event, tripID: tripID, stage: stage, attemptID: attemptID)
        } catch { failed = true }
    }

    func check() throws { if failed { throw BuildStoreError.evidenceFailed } }
}
