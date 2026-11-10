import AsyncHTTPClient
import BuildKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GuideKit
import PipelineKit
import ResponsesKit
import ServerHTTPKit
import ServerKit
import SourcesKit

public enum LiveStageError: Error, Sendable {
    case missingCheckpoint(BuildStage)
    case transport
    /// No provider runs the model id.
    case unsupportedModel
}

/// The same process-wide pacer is shared by all jobs and runner instances.
private enum SharedPacer {
    static let nominatim = RequestPacer(interval: .seconds(1))
}

private struct PoliteFetcher: HTTPFetching {
    let inner: any HTTPFetching
    func send(_ request: URLRequest) async throws -> SourcesKit.HTTPResponse {
        if request.url?.host?.lowercased() == NominatimGeocoder.host {
            try await SharedPacer.nominatim.wait()
        }
        try Task.checkCancellation()
        return try await inner.send(request)
    }
}

/// Executes exactly one durable stage. Supply an AHC client configured to disallow redirects.
public struct LiveStageRunner: Sendable {
    private let client: HTTPClient
    private let key: String
    private let model: String
    private let session: CredentialSession
    private let providers: ProviderKeys

    public init(client: HTTPClient, key: String, model: String, session: CredentialSession,
                providers: ProviderKeys = ProviderKeys(anthropic: nil, deepSeek: nil)) {
        self.client = client; self.key = key; self.model = model; self.session = session; self.providers = providers
    }

    // swiftlint:disable:next function_body_length
    public func run(_ work: BuildWork, evidence: @escaping BuildEvidenceSink) async throws -> StageResult {
        let standard = TripPreferences.standard
        let preferences = TripPreferences(pace: work.input.pace ?? standard.pace,
                                          interests: work.input.interests ?? standard.interests,
                                          dailySpend: work.input.dailySpend ?? standard.dailySpend,
                                          adults: work.input.adults ?? standard.adults,
                                          children: work.input.children ?? standard.children,
                                          mobilityNotes: work.input.mobilityNotes ?? standard.mobilityNotes)
        let input = SourceInput(destination: work.input.destination, from: work.input.from, to: work.input.to,
                                stay: work.input.stay, facts: work.input.facts, preferences: preferences)
        let record = SourceRecord { await evidence(.source($0)) }
        let pipeline = GuidePipeline()
        let emit: GuidePipeline.EvidenceSink = { await evidence(.pipeline($0)) }
        let send: GuidePipeline.Send = { try await sendResponse($0) }
        let id = work.tripID.uuidString
        // A trip may name its model; otherwise the server default is used for every AI request of the trip.
        let aiModel = work.input.model ?? model
        switch work.stage {
        case .basics:
            let fetcher = sourceFetcher(limit: 5)
            let geocoder = NominatimGeocoder(fetcher: fetcher)
            let result = try await SourcePreparation.prepareBasics(input, fetcher: fetcher,
                                                                    geocoder: geocoder, record: record)
            return try checkpoint(result)
        case .candidates:
            let basics: BasicsCheckpoint = try load(.basics, from: work)
            let fetcher = sourceFetcher(limit: 150)
            let geocoder = NominatimGeocoder(fetcher: fetcher)
            let result = try await SourcePreparation.prepareCandidates(input, basics: basics, fetcher: fetcher,
                key: key, geocoder: geocoder, record: record)
            return try checkpoint(CandidatesCheckpoint(result))
        case .research:
            let candidates: CandidatesCheckpoint = try load(.candidates, from: work)
            let fetcher = sourceFetcher(limit: 45)
            let suggestions = SuggestionPreparation(fetcher: fetcher, key: key, facts: candidates.facts.value,
                record: record, geocoder: NominatimGeocoder(fetcher: fetcher))
            let result = try await pipeline.researchStage(model: aiModel, facts: candidates.facts.value,
                measurements: candidates.measurements.value, stayArea: candidates.stayArea,
                resolveSuggestion: { try await suggestions.resolve($0) },
                prepareCandidates: { try await suggestions.prepare($0, facts: $1, measurements: $2) },
                send: send, evidence: emit)
            return try checkpoint(result)
        case .plan:
            let candidates: CandidatesCheckpoint = try load(.candidates, from: work)
            let researched: ResearchedPipeline = try load(.research, from: work)
            let question = work.input.stay == nil && work.input.facts == nil
                ? "Choose accommodation; the base is unbooked and approximate."
                : "Confirm check-in and check-out times; supplied defaults may be assumptions."
            let request: JSONValue = .object(["accommodationQuestion": .string(question)])
            let result = try await pipeline.initialPlanStage(id: id, model: aiModel, researched: researched,
                weather: candidates.weather.map(\.value), requests: request, send: send, evidence: emit)
            return try checkpoint(result)
        case .check:
            let researched: ResearchedPipeline = try load(.research, from: work)
            let planned: PlannedPipeline = try load(.plan, from: work)
            return try await checkpoint(pipeline.checkStage(id: id, model: aiModel, researched: researched,
                                                             planned: planned, send: send, evidence: emit))
        case .write:
            let candidates: CandidatesCheckpoint = try load(.candidates, from: work)
            let researched: ResearchedPipeline = try load(.research, from: work)
            let draft: PlanDraft = try load(.check, from: work)
            return try await checkpoint(pipeline.copyStage(id: id, model: aiModel, researched: researched, draft: draft,
                weather: candidates.weather.map(\.value), send: send, evidence: emit))
        case .assemble:
            let candidates: CandidatesCheckpoint = try load(.candidates, from: work)
            let researched: ResearchedPipeline = try load(.research, from: work)
            let draft: PlanDraft = try load(.check, from: work)
            let copy: GuideCopy = try load(.write, from: work)
            let guide = try await pipeline.assembleStage(id: id, researched: researched, draft: draft,
                                                          copy: copy, weather: candidates.weather.map(\.value),
                                                          evidence: emit)
            let final = assumptions(guide, input: work.input, model: aiModel)
            return StageResult(checkpoint: try JSONEncoder().encode(final), guide: final)
        }
    }

    private func sourceFetcher(limit: Int) -> CappedFetcher {
        CappedFetcher(inner: PoliteFetcher(inner: AHCFetching(client: client)), limit: limit)
    }

    /// Sends one request to the provider that runs its model. Every answer is checked for the secrets of the provider
    /// that gave it (the ChatGPT tokens, or the API key), and a secret in the answer fails the stage.
    private func sendResponse(_ request: ResponsesRequest) async throws -> ResponsesResult {
        guard let destination = ProviderRouting.destination(model: request.model, webSearch: request.webSearch) else {
            throw LiveStageError.unsupportedModel
        }
        let routed = request.replacingModel(destination.model)
        let result: ResponsesResult
        let secrets: [String]
        switch destination.provider {
        case .chatGPT:
            (result, secrets) = try await sendChatGPT(routed)
        case .claude:
            guard let anthropicKey = providers.anthropic else {
                throw ProviderError.missingKey(provider: ModelProvider.claude.rawValue)
            }
            let anthropic = AnthropicClient(transport: AHCStreamTransport(client: client), apiKey: anthropicKey)
            result = try await anthropic.send(routed)
            secrets = [anthropicKey]
        case .deepSeek:
            guard let deepSeekKey = providers.deepSeek else {
                throw ProviderError.missingKey(provider: ModelProvider.deepSeek.rawValue)
            }
            let deepSeek = ResponsesClient(transport: AHCStreamTransport(client: client), endpoint: .deepSeek)
            let outcome = await deepSeek.send(body: try routed.body(), accessToken: deepSeekKey)
            try Task.checkCancellation()
            guard let answer = outcome.result else {
                throw ProviderError.from(outcome, provider: ModelProvider.deepSeek.rawValue)
            }
            result = answer
            secrets = [deepSeekKey]
        }
        guard !Self.leaksSecret(result, secrets: secrets) else { throw LiveStageError.transport }
        return result
    }

    /// The ChatGPT route, with one retry after a refreshed token when the plan refuses the first one. Returns the
    /// tokens used, so the answer can be checked for them.
    private func sendChatGPT(_ request: ResponsesRequest) async throws -> (ResponsesResult, [String]) {
        let body = try request.body()
        let transport = ResponsesClient(transport: AHCStreamTransport(client: client))
        var credentials = try await session.credentials()
        var tokens = [credentials.accessToken]
        var outcome = await transport.send(body: body, accessToken: credentials.accessToken)
        try Task.checkCancellation()
        if outcome.status == 401 {
            credentials = try await session.credentials(forceRefresh: true)
            tokens.append(credentials.accessToken)
            outcome = await transport.send(body: body, accessToken: credentials.accessToken)
            try Task.checkCancellation()
        }
        guard let result = outcome.result else {
            throw LiveStageError.transport
        }
        return (result, tokens)
    }

    /// True when a secret is empty or appears in the answer or its source and citation URLs.
    private static func leaksSecret(_ result: ResponsesResult, secrets: [String]) -> Bool {
        secrets.contains { secret in
            secret.isEmpty
                || result.text.contains(secret)
                || result.sourceURLs.contains(where: { $0.contains(secret) })
                || result.citationURLs.contains(where: { $0.contains(secret) })
        }
    }
}

private func load<T: Decodable>(_ stage: BuildStage, from work: BuildWork) throws -> T {
    guard let data = work.checkpoints[stage] else { throw LiveStageError.missingCheckpoint(stage) }
    return try JSONDecoder().decode(T.self, from: data)
}

private func checkpoint<T: Encodable>(_ value: T) throws -> StageResult {
    StageResult(checkpoint: try JSONEncoder().encode(value))
}

/// Adds the open questions for a trip that has no supplied facts, and records the model that wrote the guide.
private func assumptions(_ guide: Guide, input: TripBuildInput, model: String) -> Guide {
    guard input.facts == nil else { return guide.recordingAIModel(model) }
    var questions = guide.openQuestions ?? []
    if input.stay == nil { questions.append("Choose accommodation; the base is an approximate placeholder.") }
    questions.append("Confirm check-in and check-out; 15:00 and 11:00 are assumptions, not confirmed.")
    questions.append("Confirm the assumed budget currency.")
    return Guide(id: guide.id, version: guide.version, status: guide.status, trip: guide.trip,
                 bookings: guide.bookings, stay: guide.stay, places: guide.places, days: guide.days,
                 lists: guide.lists, tasting: guide.tasting, practical: guide.practical, sources: guide.sources,
                 hero: guide.hero, notes: guide.notes, openQuestions: questions, aiModel: model)
}
