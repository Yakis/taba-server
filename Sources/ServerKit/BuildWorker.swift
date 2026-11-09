import Foundation
import Jobs
import JobsPostgres
import PostgresMigrations
import ServiceLifecycle

public struct StageJob: JobParameters {
    public static let jobName = "taba-stage-v1"
    public let tripID: UUID
    public let stage: BuildStage

    public init(tripID: UUID, stage: BuildStage) {
        self.tripID = tripID
        self.stage = stage
    }
}

/// Polls the durable successor outbox. Failed dispatch is retried, not lost. Stages themselves are
/// never retried on ordinary errors; only interrupted attempts can be recovered by the outbox.
public struct BuildDispatcher: Service {
    let store: PostgresTripStore
    let queue: JobQueue<PostgresJobQueue>
    let migrations: DatabaseMigrations

    public init(store: PostgresTripStore, queue: JobQueue<PostgresJobQueue>, migrations: DatabaseMigrations) {
        self.store = store; self.queue = queue; self.migrations = migrations
    }

    public func run() async throws {
        do {
            try await cancelWhenGracefulShutdown {
                try await migrations.waitUntilCompleted()
                while !Task.isCancelled {
                    do { try await store.dispatch(queue: queue) } catch {
                        if Task.isCancelled { return }
                        // No SQL, inputs or raw provider errors in logs.
                        store.logger.warning("Build dispatch unavailable; will retry")
                    }
                    try await Task.sleep(for: .seconds(1))
                }
            }
        } catch is CancellationError {
            // Graceful shutdown cancels this polling service; it is not a server failure.
        }
    }
}
