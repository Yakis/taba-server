@testable import BuildKit
import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit
import Testing

/// Answers each request by its host, and keeps the requests it saw. No network is used.
private actor ByHostFetcher: HTTPFetching {
    private let answer: @Sendable (URLRequest) -> HTTPResponse
    private(set) var requests: [URLRequest] = []

    init(answer: @escaping @Sendable (URLRequest) -> HTTPResponse) {
        self.answer = answer
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return answer(request)
    }

    func count(host: String) -> Int {
        requests.filter { $0.url?.host == host }.count
    }
}

/// The evidence events a run wrote, in order.
private actor EvidenceLog {
    private(set) var events: [[String: JSONValue]] = []

    func add(_ event: [String: JSONValue]) {
        events.append(event)
    }

    var names: [String] {
        events.compactMap { event in
            if case .string(let name)? = event["event"] { return name }
            return nil
        }
    }

    /// True when some event has this name and result, and, when `source` is given, that source too.
    func contains(event name: String, result: String, source: String?) -> Bool {
        events.contains { fields in
            guard case .string(let eventName)? = fields["event"], eventName == name,
                  case .string(let outcome)? = fields["result"], outcome == result
            else {
                return false
            }
            guard let source else { return true }
            if case .string(let origin)? = fields["source"] { return origin == source }
            return false
        }
    }
}

private let foursquareHost = "places-api.foursquare.com"
private let overpassHost = "overpass-api.de"

/// OpenStreetMap elements in the shape `out tags center` returns, written by hand. A music venue with hours, a park and
/// a cafe. Every Overpass query in these tests gets this answer.
private let overpassJSON = """
{"elements":[
  {"type":"node","id":7,"lat":55.95030,"lon":-3.20030,
   "tags":{"name":"The Venue Room","amenity":"music_venue","opening_hours":"Mo-Su 10:00-22:00"}},
  {"type":"node","id":8,"lat":55.95100,"lon":-3.20100,
   "tags":{"name":"Quiet Park","leisure":"park"}},
  {"type":"node","id":9,"lat":55.95110,"lon":-3.20110,
   "tags":{"name":"Corner Cafe","amenity":"cafe"}}
]}
"""

/// One Foursquare hit, written by hand in the shape the search returns.
private let foursquareHitJSON = """
{"results":[{"fsq_place_id":"abc","name":"Fsq Cafe","latitude":55.9502,"longitude":-3.2002,
  "categories":[{"fsq_category_id":"63be6904847c3692a84b9bb6","name":"Coffee Shop"}],
  "location":{"address":"1 Test Road","formatted_address":"1 Test Road, Edinburgh"}}]}
"""

private func reply(_ body: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, body: Data(body.utf8), headers: [:])
}

/// Foursquare answers with `foursquare`. Overpass answers with `overpass`.
private func byHost(
    foursquare: HTTPResponse,
    overpass: HTTPResponse = reply(overpassJSON)
) -> @Sendable (URLRequest) -> HTTPResponse {
    { request in
        request.url?.host == foursquareHost ? foursquare : overpass
    }
}

private func sourceInput(interests: [String] = []) throws -> SourceInput {
    let day = try #require(LocalDate("2026-11-14"))
    return SourceInput(destination: "Edinburgh", from: day, to: day, preferences: TripPreferences(interests: interests))
}

private func fixtureFacts() throws -> TripFacts {
    let url = URL(fileURLWithPath: "GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
    let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
    return TripFacts(trip: guide.trip, bookings: guide.bookings, stay: guide.stay, places: guide.places,
                     practical: guide.practical, sources: guide.sources)
}

/// What the candidate sweep added, the interest labels it gave, and the evidence it wrote.
private struct CandidateRun {
    let places: [String: Place]
    let sources: [Source]
    let labels: [String: [String]]
    let log: EvidenceLog
    let lookupFailed: Bool
}

struct OSMFallbackTests {
    /// Runs the candidate sweep, returning what it added and the evidence it wrote.
    private func collect(
        _ fetcher: ByHostFetcher,
        interests: [String] = []
    ) async throws -> CandidateRun {
        let log = EvidenceLog()
        let centre = try #require(Coordinate(latitude: 55.9500, longitude: -3.2000))
        let today = try #require(LocalDate("2026-11-14"))
        var places: [String: Place] = [:]
        var sources: [Source] = []
        let (lookup, labels) = try await SourcePreparation.collectCandidates(
            try sourceInput(interests: interests), fetcher: CappedFetcher(inner: fetcher, limit: 150),
            key: "test-key-not-real", today: today, centre: centre, seed: nil, places: &places, sources: &sources,
            record: SourceRecord { await log.add($0) })
        return CandidateRun(places: places, sources: sources, labels: labels, log: log,
                            lookupFailed: lookup.error != nil)
    }

    // MARK: The candidate sweep

    @Test func theOpenStreetMapSweepIsUsedWhenEveryFoursquareRequestIsRefused() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply("{}", status: 429)))
        // Eight base searches and two interest searches, each refused.
        let result = try await collect(fetcher, interests: ["Music", "Parks"])
        #expect(Set(result.places.keys) == ["osm:node/7", "osm:node/8", "osm:node/9"])
        #expect(await fetcher.count(host: foursquareHost) == 10)
        #expect(await fetcher.count(host: overpassHost) == 1)
        let names = await result.log.names
        #expect(names.contains("foursquareSweep"))
        #expect(names.contains("osmSweep"))
        #expect(!result.lookupFailed)
    }

    @Test func theOpenStreetMapPlacesKeepTheirHoursAndTheirSources() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply("{}", status: 429)))
        let result = try await collect(fetcher, interests: ["Music", "Parks"])
        #expect(result.places["osm:node/7"]?.hours.hoursKnown == true)
        #expect(result.places["osm:node/8"]?.hours.hoursKnown == false)
        #expect(result.places["osm:node/8"]?.kind == .landmark)
        #expect(result.sources.map(\.id) == ["osm:node/7"])
    }

    @Test func theOpenStreetMapSweepIsNotUsedWhenFoursquareGivesPlaces() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply(foursquareHitJSON)))
        let result = try await collect(fetcher)
        #expect(!(await result.log.names).contains("osmSweep"))
        #expect(Set(result.places.keys) == ["fsq:abc"])
        #expect(result.sources.contains { $0.id == FoursquarePlacesSource.sourceId })
        // The only Overpass traffic is the hours lookup for the Foursquare place.
        #expect(await fetcher.count(host: overpassHost) == 1)
    }

    @Test func noCandidatesIsThrownWhenBothSourcesFindNothing() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply("{}", status: 429),
                                                   overpass: reply("{}", status: 400)))
        await #expect(throws: SourcePreparationError.noCandidates) {
            _ = try await self.collect(fetcher)
        }
    }

    @Test func interestLabelsComeFromTheOpenStreetMapSweep() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply("{}", status: 429)))
        let result = try await collect(fetcher, interests: ["Music", "Parks"])
        #expect(result.labels["osm:node/7"] == ["music"])
        #expect(result.labels["osm:node/8"] == ["parks"])
        #expect(result.labels["osm:node/9"] == nil)
    }

    // MARK: Suggestions

    private func suggestion(_ name: String) -> SuggestedPlace {
        SuggestedPlace(name: name, area: "New Town", kind: .venue, why: "Live music most nights.")
    }

    @Test func aSuggestionFallsBackToOpenStreetMapAfterAFoursquareRefusal() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply("{}", status: 429)))
        let log = EvidenceLog()
        let service = SuggestionPreparation(fetcher: CappedFetcher(inner: fetcher, limit: 50),
                                            key: "test-key-not-real", facts: try fixtureFacts(),
                                            record: SourceRecord { await log.add($0) })
        let place = try #require(try await service.resolve(suggestion("The Venue Room")))
        #expect(place.id == "osm:node/7")
        #expect(place.kind == .venue)
        #expect(await fetcher.count(host: foursquareHost) == 1)
        #expect(await log.contains(event: "suggestion", result: "matched", source: "osm"))
    }

    @Test func theSuggestionsAfterARefusalSkipFoursquare() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply("{}", status: 429)))
        let service = SuggestionPreparation(fetcher: CappedFetcher(inner: fetcher, limit: 50),
                                            key: "test-key-not-real", facts: try fixtureFacts(),
                                            record: SourceRecord { _ in })
        _ = try await service.resolve(suggestion("The Venue Room"))
        let second = try #require(try await service.resolve(suggestion("The Venue Room")))
        #expect(second.id == "osm:node/7")
        #expect(await fetcher.count(host: foursquareHost) == 1)
        #expect(await fetcher.count(host: overpassHost) == 2)
    }

    @Test func aSuggestionWithNoMatchIsUnmatchedNotFailed() async throws {
        let fetcher = ByHostFetcher(answer: byHost(foursquare: reply("{}", status: 429)))
        let log = EvidenceLog()
        let service = SuggestionPreparation(fetcher: CappedFetcher(inner: fetcher, limit: 50),
                                            key: "test-key-not-real", facts: try fixtureFacts(),
                                            record: SourceRecord { await log.add($0) })
        let place = try await service.resolve(suggestion("Lighthouse Chandlery"))
        #expect(place == nil)
        #expect(await log.contains(event: "suggestion", result: "unmatched", source: "osm"))
    }
}
