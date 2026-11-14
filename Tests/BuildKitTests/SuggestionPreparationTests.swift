@testable import BuildKit
import Foundation
import GuideKit
@testable import PipelineKit
import SourcesKit
import Testing

private actor StubFetcher: HTTPFetching {
    private let body: String

    init(body: String) {
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        HTTPResponse(status: 200, body: Data(body.utf8), headers: [:])
    }
}

private func fixtureFacts() throws -> TripFacts {
    let url = URL(fileURLWithPath: "GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
    let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
    return TripFacts(trip: guide.trip, bookings: guide.bookings, stay: guide.stay, places: guide.places,
                     practical: guide.practical, sources: guide.sources)
}

/// A copy of a fixture place with another kind and indoor flag.
private func place(_ base: Place, kind: PlaceKind, indoor: Bool) -> Place {
    Place(id: base.id, name: base.name, kind: kind, location: base.location, hours: base.hours,
          priceLevel: base.priceLevel, booking: base.booking, indoor: indoor, images: base.images, facts: base.facts,
          copy: base.copy)
}

private func measurements(_ labels: [String: [String]]) -> PipelineInputMeasurements {
    PipelineInputMeasurements(areas: [:], walkFromBase: [:], areaWalkMinutes: .object([:]),
                              arrivalWalkMinutes: 0, departureWalkMinutes: 0, searchLabels: labels)
}

/// A suggestion service over `fetcher`, with no waits between its OpenStreetMap requests.
private func service(_ fetcher: ByHostFetcher, facts: TripFacts, record: SourceRecord = SourceRecord { _ in })
    -> SuggestionPreparation {
    let capped = CappedFetcher(inner: fetcher, limit: 50)
    return SuggestionPreparation(fetcher: capped, facts: facts, record: record, geocoder: nil,
                                 openStreetMap: zeroWaits(capped))
}

/// A suggested venue with the given name, as research gives one.
private func venue(_ name: String) -> SuggestedPlace {
    SuggestedPlace(name: name, area: "New Town", kind: .venue, why: "Live music most nights.")
}

struct SuggestionPreparationTests {
    @Test func aSuggestedStreetStaysOutdoorsWhenTheSourceCallsItOther() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let draft = place(base, kind: .other, indoor: true)
        let kept = SuggestionPreparation.keepingSuggestedKind(draft, suggested: .street)
        #expect(kept.kind == .street)
        #expect(!kept.indoor)
        #expect(kept.id == draft.id && kept.name == draft.name && kept.location == draft.location)
    }

    @Test func aSuggestedViewpointStaysOutdoorsWhenTheSourceCallsItLandmark() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let kept = SuggestionPreparation.keepingSuggestedKind(place(base, kind: .landmark, indoor: true),
                                                              suggested: .viewpoint)
        #expect(kept.kind == .viewpoint)
        #expect(!kept.indoor)
    }

    @Test func otherSuggestionsComeBackUntouched() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let pub = place(base, kind: .pub, indoor: true)
        #expect(SuggestionPreparation.keepingSuggestedKind(pub, suggested: .restaurant) == pub)
        let museum = place(base, kind: .museum, indoor: true)
        #expect(SuggestionPreparation.keepingSuggestedKind(museum, suggested: .street) == museum)
    }

    @Test func resolveKeepsAStreetOutdoorsWhenTheHitIsOther() async throws {
        let body = """
        [{"osm_type":"way","osm_id":5,"lat":"55.9548","lon":"-3.2046","category":"highway","type":"residential",
          "name":"Circus Lane","importance":0.1}]
        """
        let fetcher = ByHostFetcher(answer: byHost(nominatim: reply(body)))
        let suggestion = SuggestedPlace(name: "Circus Lane", area: "New Town", kind: .street, why: "Colourful doors.")
        let found = try #require(try await service(fetcher, facts: try fixtureFacts()).resolve(suggestion))
        #expect(found.kind == .street)
        #expect(!found.indoor)
    }

    @Test func aSuggestionIsMatchedByNominatimWithNoOtherRequest() async throws {
        let fetcher = ByHostFetcher(answer: byHost())
        let log = EvidenceLog()
        let prepared = service(fetcher, facts: try fixtureFacts(), record: SourceRecord { await log.add($0) })
        let found = try #require(try await prepared.resolve(venue("The Venue Room")))
        #expect(found.id == "osm:node/7")
        #expect(found.kind == .venue)
        #expect(await fetcher.count(host: nominatimHost) == 1)
        #expect(await fetcher.count(host: overpassHost) == 0)
        #expect(await log.contains(event: "suggestion", result: "matched", source: "nominatim"))
        #expect(await fetcher.count(host: foursquareHost) == 0)
    }

    @Test func aSuggestionFallsBackToOverpassWhenNominatimFails() async throws {
        let fetcher = ByHostFetcher(answer: byHost(nominatim: reply("", status: 503)))
        let log = EvidenceLog()
        let prepared = service(fetcher, facts: try fixtureFacts(), record: SourceRecord { await log.add($0) })
        let found = try #require(try await prepared.resolve(venue("The Venue Room")))
        #expect(found.id == "osm:node/7")
        #expect(await fetcher.count(host: overpassHost) == 1)
        #expect(await log.contains(event: "suggestion", result: "failed", source: "nominatim"))
        #expect(await log.contains(event: "suggestion", result: "matched", source: "osm"))
        #expect(await fetcher.count(host: foursquareHost) == 0)
    }

    @Test func aNominatimAnswerWithNoMatchIsFinal() async throws {
        let fetcher = ByHostFetcher(answer: byHost())
        let log = EvidenceLog()
        let prepared = service(fetcher, facts: try fixtureFacts(), record: SourceRecord { await log.add($0) })
        let found = try await prepared.resolve(venue("Lighthouse Chandlery"))
        #expect(found == nil)
        #expect(await log.contains(event: "suggestion", result: "unmatched", source: "nominatim"))
        // Nominatim answered, so Overpass is not asked.
        #expect(await fetcher.count(host: overpassHost) == 0)
        #expect(await fetcher.count(host: foursquareHost) == 0)
    }

    @Test func anExistingCandidateIsFoundByNameWithNoRequest() async throws {
        let facts = try fixtureFacts()
        let base = try #require(facts.places.values.first)
        let fetcher = ByHostFetcher(answer: byHost())
        let log = EvidenceLog()
        let prepared = service(fetcher, facts: facts, record: SourceRecord { await log.add($0) })
        let suggestion = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Good light")
        let found = try await prepared.resolve(suggestion)
        #expect(found?.id == base.id)
        #expect(await fetcher.requests.isEmpty)
        #expect(await log.contains(event: "suggestion", result: "existing", source: nil))
    }

    @Test func theTwentyFirstSuggestionIsNil() async throws {
        let fetcher = ByHostFetcher(answer: byHost())
        let prepared = service(fetcher, facts: try fixtureFacts())
        #expect(SuggestionPreparation.maximumSuggestions == 20)
        for _ in 0..<SuggestionPreparation.maximumSuggestions {
            _ = try await prepared.resolve(venue("The Venue Room"))
        }
        let requests = (await fetcher.requests).count
        #expect(try await prepared.resolve(venue("The Venue Room")) == nil)
        #expect((await fetcher.requests).count == requests)
        #expect(await fetcher.count(host: foursquareHost) == 0)
    }

    @Test func researchInterestsBecomeLabelsOnTheirPlace() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let suggestion = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Good light",
                                        interests: ["Photography", "Photography", " "])
        let verified = VerifiedResearch(result: ResearchResult(findings: [], suggestedPlaces: [suggestion],
                                                               searchNotes: ""), places: [base])
        let labelled = SuggestionPreparation.withResearchLabels(measurements([base.id: ["music"]]), verified)
        #expect(labelled.searchLabels[base.id] == ["interest:Photography", "music", "research"])
        let served = InterestMatch.interests(for: ["Photography"], kind: .other, indoor: true,
                                             searchLabels: labelled.searchLabels[base.id] ?? [])
        #expect(served == ["Photography"])
    }

    @Test func everyVerifiedPlaceGetsTheResearchLabelWithoutInterests() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let plain = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Old research")
        let verified = VerifiedResearch(result: ResearchResult(findings: [], suggestedPlaces: [plain],
                                                               searchNotes: ""), places: [base])
        let labelled = SuggestionPreparation.withResearchLabels(measurements([base.id: ["music"]]), verified)
        #expect(labelled.searchLabels[base.id] == ["music", "research"])
    }

    @Test func researchLabelsAreSortedWithoutDuplicates() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let suggestion = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Good light",
                                        interests: ["Photography", "Photography"])
        let verified = VerifiedResearch(result: ResearchResult(findings: [], suggestedPlaces: [suggestion],
                                                               searchNotes: ""), places: [base])
        let labelled = SuggestionPreparation.withResearchLabels(measurements([base.id: ["research", "zebra"]]),
                                                                verified)
        #expect(labelled.searchLabels[base.id] == ["interest:Photography", "research", "zebra"])
    }

    @Test func preparingWithoutNewPlacesStillLabelsThem() async throws {
        let facts = try fixtureFacts()
        let base = try #require(facts.places.values.first)
        let suggestion = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Good light",
                                        interests: ["Photography"])
        let verified = VerifiedResearch(result: ResearchResult(findings: [], suggestedPlaces: [suggestion],
                                                               searchNotes: ""), places: [base])
        let service = SuggestionPreparation(fetcher: CappedFetcher(inner: StubFetcher(body: "{}"), limit: 10),
                                            facts: facts, record: SourceRecord { _ in })
        let (prepared, labelled) = try await service.prepare(verified, facts: facts,
                                                             measurements: measurements([:]))
        #expect(prepared.places == facts.places)
        #expect(labelled.searchLabels[base.id] == ["interest:Photography", "research"])
    }
}
