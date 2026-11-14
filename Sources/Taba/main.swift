#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import BuildKit
import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

@main
struct Taba {
    static func main() async {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            try await run(options)
        } catch {
            let message: String
            switch error {
            case CLIError.usage:
                message = "Usage: taba build --destination NAME --from YYYY-MM-DD --to YYYY-MM-DD "
                    + "[--stay NAME] [--luggage NAME] [--hand-luggage-only] [--model MODEL] "
                    + "[--out DIRECTORY] [--facts GUIDE.json]"
            case CLIError.factsMismatch, SourcePreparationError.factsMismatch:
                message = "Facts do not match the requested trip or are missing the stay."
            case CLIError.missingStay: message = "Supply --stay when building without --facts."
            case CLIError.geocoding, SourcePreparationError.geocoding:
                message = "Could not geocode the destination or stay."
            case CLIError.noCandidates, SourcePreparationError.noCandidates: message = "No candidate places were found."
            case CLIError.output:
                message = "Could not create a new output directory; existing output is never overwritten."
            case CLIError.recording: message = "Could not persist the run record."
            default: message = "Build failed. Check the run record and source availability."
            }
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }

    static func run(_ options: Options) async throws {
        let directory: URL
        if let output = options.out {
            directory = URL(fileURLWithPath: output, isDirectory: true)
        } else {
            let root = URL(fileURLWithPath: "probe-output/runs", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let name = ISO8601DateFormatter().string(from: Date()) + "-" + UUID().uuidString
            directory = root.appendingPathComponent(name, isDirectory: true)
        }
        guard mkdir(directory.path, 0o700) == 0 else { throw CLIError.output }
        let record = try RunRecord(directory: directory)
        print("Run record: \(directory.appendingPathComponent("run.json").path)")
        await record.append(["event": .string("started"), "model": .string(options.model)])
        do {
            let session = CredentialSession(store: .defaultStore, tokenClient: TokenClient())
            _ = try await session.credentials()
            let fetcher = CappedFetcher(inner: URLSessionFetcher(), limit: 150)
            let prepared = try await SourcePreparation.prepare(options, fetcher: fetcher, record: record)
            let suggestions = SuggestionPreparation(fetcher: fetcher, facts: prepared.facts, record: record)
            let client = ResponsesClient()
            let built = try await GuidePipeline().run(
                id: UUID().uuidString, model: options.model, facts: prepared.facts,
                measurements: prepared.measurements, weather: prepared.weather, stayArea: prepared.stayArea,
                requests: .object([:]),
                resolveSuggestion: { try await suggestions.resolve($0) },
                prepareCandidates: { try await suggestions.prepare($0, facts: $1, measurements: $2) },
                send: { request in
                    try await send(request, session: session, client: client, record: record)
                }, evidence: { event in await record.record(event) }
            )
            let guide = built.recordingAIModel(options.model)
            try await record.check()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(guide).write(to: directory.appendingPathComponent("guide.json"),
                                            options: .withoutOverwriting)
            print("Guide: \(directory.appendingPathComponent("guide.json").path)")
        } catch {
            await record.append(["event": .string("failed"), "category": .string(failureCategory(error))])
            print("Run record: \(directory.appendingPathComponent("run.json").path)")
            throw error
        }
    }

    static func failureCategory(_ error: any Error) -> String {
        switch error {
        case is CancellationError: "cancelled"
        case CLIError.geocoding, SourcePreparationError.geocoding: "geocoding"
        case CLIError.noCandidates, SourcePreparationError.noCandidates: "noCandidates"
        case CLIError.recording: "recording"
        case is CredentialSessionError: "credentials"
        default: "pipelineOrSourceFailure"
        }
    }

    static func send(_ request: ResponsesRequest, session: CredentialSession, client: ResponsesClient,
                     record: RunRecord) async throws -> ResponsesResult {
        let body = try request.body()
        var credentials = try await session.credentials()
        var outcome = await client.send(body: body, accessToken: credentials.accessToken)
        try Task.checkCancellation()
        await record.transport(outcome, attempt: 1)
        if outcome.status == 401 {
            credentials = try await session.credentials(forceRefresh: true)
            outcome = await client.send(body: body, accessToken: credentials.accessToken)
            try Task.checkCancellation()
            await record.transport(outcome, attempt: 2)
        }
        guard let result = outcome.result,
              !result.text.contains(credentials.accessToken),
              !result.sourceURLs.contains(where: { $0.contains(credentials.accessToken) }),
              !result.citationURLs.contains(where: { $0.contains(credentials.accessToken) }) else {
            throw CLIError.service
        }
        return result
    }
}
