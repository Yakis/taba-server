import AsyncHTTPClient
import Foundation
import Hummingbird
import Jobs
import JobsPostgres
import LivePipelineKit
import Logging
import PostgresMigrations
import PostgresNIO
import ResponsesKit
import ServerHTTPKit
import ServerKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

@main
struct TabaServer {
    enum ConfigurationError: Error { case missingToken, missingKey, invalidPort }

    static func main() async {
        do { try await run() } catch {
            // Never print underlying SQL/provider errors: they may contain private data.
            let message = "TABA server stopped: check configuration and database availability.\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }

    // swiftlint:disable:next function_body_length
    static func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["TABA_APP_TOKEN"], token.utf8.count >= 32 else {
            throw ConfigurationError.missingToken
        }
        guard let port = Int(environment["PORT"] ?? "8090"), (1...65535).contains(port),
              let databasePort = Int(environment["DB_PORT"] ?? "5432"), (1...65535).contains(databasePort) else {
            throw ConfigurationError.invalidPort
        }
        var logger = Logger(label: "taba-server")
        logger.logLevel = .notice
        let privateLogger: Logger = {
            var value = Logger(label: "taba-storage")
            value.logLevel = .critical
            return value
        }()
        let postgres = PostgresClient(configuration: .init(
            host: environment["DB_HOST"] ?? "localhost", port: databasePort,
            username: environment["DB_USER"] ?? "taba", password: environment["DB_PASSWORD"] ?? "taba-local-only",
            database: environment["DB_NAME"] ?? "taba", tls: .disable), backgroundLogger: privateLogger)
        let migrations = DatabaseMigrations()
        await migrations.add(BuildMigration())
        await migrations.add(BuildAttemptMigration())
        await migrations.add(BuildModelMigration())
        let queue = await JobQueue(.postgres(client: postgres, migrations: migrations,
            configuration: .init(queueName: "taba"), logger: privateLogger), logger: privateLogger)
        let store = PostgresTripStore(client: postgres, logger: privateLogger)
        // A request's own timeout only covers the response head. The read timeout bounds idle gaps in a
        // streamed body, so a stalled provider stream cannot hold the single worker forever.
        let client = HTTPClient(configuration: .init(redirectConfiguration: .disallow,
            timeout: .init(connect: .seconds(15), read: .minutes(10))))
        do {
            // The default model is used by trips that name none. It is also the only model offered offline.
            let defaultModel = environment["TABA_MODEL"] ?? "gpt-6.1-sol"
            let runner: StageRunner
            let models: any TripModelCatalog
            switch try ServerMode.parse(environment) {
            case .replay(let directory):
                let replay = try ReplayStageRunner(directory: directory)
                runner = { try await replay.run($0, evidence: $1) }
                models = FixedModelCatalog(defaultModel: defaultModel)
                logger.notice("Offline replay mode; no provider requests will be sent")
            case .live:
                guard let key = environment["FOURSQUARE_API_KEY"], !key.isEmpty else {
                    throw ConfigurationError.missingKey
                }
                let session = CredentialSession(store: .defaultStore,
                    tokenClient: TokenClient(transport: AHCOAuthTransport(client: client)))
                let live = LiveStageRunner(client: client, key: key, model: defaultModel, session: session)
                runner = { try await live.run($0, evidence: $1) }
                models = ModelCatalog.live(defaultModel: defaultModel, session: session,
                    client: ModelsClient(transport: AHCOAuthTransport(client: client)))
            }
            queue.registerJob(JobDefinition(parameters: StageJob.self, retryStrategy: .dontRetry) { job, _ in
                try await store.process(job, runner: runner)
            })
            let router = try TripHTTP.router(store: store, token: token, models: models)
            var application = Application(router: router,
                configuration: .init(address: .hostname(environment["HOST"] ?? "127.0.0.1", port: port)),
                services: [postgres, queue.processor(options: .init(numWorkers: 1)),
                           BuildDispatcher(store: store, queue: queue, migrations: migrations)], logger: logger)
            application.beforeServerStarts {
                try await migrations.apply(client: postgres, logger: privateLogger, dryRun: false)
            }
            try await application.runService()
            try await client.shutdown()
        } catch {
            try? await client.shutdown()
            throw error
        }
    }
}
