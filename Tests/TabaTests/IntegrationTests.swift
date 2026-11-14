import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit
@testable import Taba
import Testing

/// Answers every request with one Nominatim row named "Unique Museum", and counts the requests.
private actor SearchFetcher: HTTPFetching {
    var count = 0
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        count += 1
        let body = """
        [{"osm_type":"node","osm_id":1,"lat":"55.95","lon":"-3.19","category":"tourism","type":"museum",
          "name":"Unique Museum","importance":0.5}]
        """
        return HTTPResponse(status: 200, body: Data(body.utf8), headers: [:])
    }
}

private func fixture() throws -> Guide {
    let url = URL(fileURLWithPath: "GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
    return try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
}

@Test func currencyIsDestinationAware() {
    #expect(SourcePreparation.currency(for: "GB") == "GBP")
    #expect(SourcePreparation.currency(for: "us") == "USD")
    #expect(SourcePreparation.currency(for: "FR") == "EUR")
    #expect(SourcePreparation.currency(for: "JP") == "XXX")
}

@Test func researchMatchesASuggestionThroughNominatim() async throws {
    let guide = try fixture()
    let facts = TripFacts(trip: guide.trip, bookings: guide.bookings, stay: guide.stay,
                          places: guide.places, practical: guide.practical, sources: guide.sources)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let record = try RunRecord(directory: folder)
    let source = SearchFetcher()
    // The cap and the request bounds are tested in BuildKit with no waits; this one goes through the live pacing.
    let service = SuggestionPreparation(fetcher: CappedFetcher(inner: source, limit: 150),
                                        facts: facts, record: record)
    let suggestion = SuggestedPlace(name: "Unique Museum", area: "", kind: .museum, why: "Interesting")
    let result = try await service.resolve(suggestion)
    #expect(result?.name == "Unique Museum")
    #expect(await source.count == 1)
}

@Test func existingCandidateAvoidsProvider() async throws {
    let guide = try fixture()
    let facts = TripFacts(trip: guide.trip, bookings: guide.bookings, stay: guide.stay,
                          places: guide.places, practical: guide.practical, sources: guide.sources)
    let place = try #require(guide.stayPlace)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let fetcher = SearchFetcher()
    let service = try SuggestionPreparation(fetcher: CappedFetcher(inner: fetcher, limit: 150),
        facts: facts, record: RunRecord(directory: folder))
    let suggestion = SuggestedPlace(name: place.name, area: "", kind: place.kind, why: "Interesting")
    #expect(try await service.resolve(suggestion)?.id == place.id)
    #expect(await fetcher.count < 1)
}

@Test func tripWithoutAStayHasNoStayPlaceOrAccommodationFact() async throws {
    let options = try Options.parse(["build", "--destination", "Example", "--from", "2025-11-23",
                                     "--to", "2025-11-25"])
    let centre = try #require(Coordinate(latitude: 55.95, longitude: -3.19))
    let fetcher = SearchFetcher()
    let facts = try await SourcePreparation.baseFacts(options, seed: nil, centre: centre, country: "US",
        timeZone: "Europe/London", geocoder: NominatimGeocoder(fetcher: fetcher))
    #expect(facts.stay.placeId == nil)
    #expect(facts.stay.arrangement == .unknown)
    #expect(facts.places.values.allSatisfy { $0.kind != .lodging })
    #expect(facts.bookings.isEmpty)
    #expect(facts.trip.budget.currencyCode == "USD")
    #expect(await fetcher.count < 1)
    var sources: [Source] = []
    let assumptions = SourcePreparation.assumptions(options, seed: nil, today: options.from, facts: facts,
                                                    sources: &sources)
    #expect(assumptions.isEmpty)
    #expect(sources.isEmpty)
}

@Test func transportEvidenceNeverIncludesErrorText() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let record = try RunRecord(directory: folder)
    let secret = "test-secret-never-record" // privacy-scan:allow
    await record.transport(ResponsesOutcome(result: nil, error: .transport(secret), rawBody: secret, status: 401),
                           attempt: 1)
    let text = try String(contentsOf: folder.appendingPathComponent("run.json"), encoding: .utf8)
    #expect(!text.contains(secret))
    #expect(text.contains("401"))
    #expect(text.contains("transport"))
}
