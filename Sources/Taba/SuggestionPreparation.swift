import BuildKit
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

actor SuggestionPreparation {
    private let service: BuildKit.SuggestionPreparation
    private let record: RunRecord

    init(fetcher: CappedFetcher, key: String, facts: TripFacts, record: RunRecord) {
        self.record = record
        self.service = BuildKit.SuggestionPreparation(fetcher: fetcher, key: key, facts: facts,
                                                       record: SourceRecord { await record.append($0) })
    }

    func resolve(_ suggestion: SuggestedPlace) async throws -> Place? {
        try await service.resolve(suggestion)
    }

    func prepare(_ verified: VerifiedResearch, facts: TripFacts, measurements: PipelineInputMeasurements) async throws
        -> (TripFacts, PipelineInputMeasurements) {
        let result = try await service.prepare(verified, facts: facts, measurements: measurements)
        try await record.check()
        return result
    }
}
