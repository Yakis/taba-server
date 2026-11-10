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
    PipelineInputMeasurements(areas: [:], walkFromStay: [:], areaWalkMinutes: .object([:]),
                              arrivalWalkMinutes: 0, departureWalkMinutes: 0, searchLabels: labels)
}

struct SuggestionPreparationTests {
    @Test func aSuggestedStreetStaysOutdoorsWhenFoursquareCallsItOther() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let draft = place(base, kind: .other, indoor: true)
        let kept = SuggestionPreparation.keepingSuggestedKind(draft, suggested: .street)
        #expect(kept.kind == .street)
        #expect(!kept.indoor)
        #expect(kept.id == draft.id && kept.name == draft.name && kept.location == draft.location)
    }

    @Test func aSuggestedViewpointStaysOutdoorsWhenFoursquareCallsItLandmark() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let kept = SuggestionPreparation.keepingSuggestedKind(place(base, kind: .landmark, indoor: true),
                                                              suggested: .viewpoint)
        #expect(kept.kind == .viewpoint)
        #expect(!kept.indoor)
    }

    @Test func otherSuggestionsComeBackUntouched() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let pub = place(base, kind: .other, indoor: true)
        #expect(SuggestionPreparation.keepingSuggestedKind(pub, suggested: .pub) == pub)
        let museum = place(base, kind: .museum, indoor: true)
        #expect(SuggestionPreparation.keepingSuggestedKind(museum, suggested: .street) == museum)
    }

    @Test func resolveKeepsAStreetOutdoorsWhenTheHitIsOther() async throws {
        let body = """
        {"results":[{"fsq_place_id":"circus","name":"Circus Lane","latitude":55.9548,"longitude":-3.2046,
        "categories":[{"fsq_category_id":"n","name":"Neighborhood"}]}]}
        """
        let service = SuggestionPreparation(fetcher: CappedFetcher(inner: StubFetcher(body: body), limit: 150),
                                            key: "test-key-not-real", facts: try fixtureFacts(),
                                            record: SourceRecord { _ in })
        let suggestion = SuggestedPlace(name: "Circus Lane", area: "New Town", kind: .street, why: "Colourful doors.")
        let place = try #require(try await service.resolve(suggestion))
        #expect(place.kind == .street)
        #expect(!place.indoor)
    }

    @Test func researchInterestsBecomeLabelsOnTheirPlace() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let suggestion = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Good light",
                                        interests: ["Photography", "Photography", " "])
        let verified = VerifiedResearch(result: ResearchResult(findings: [], suggestedPlaces: [suggestion],
                                                               searchNotes: ""), places: [base])
        let labelled = SuggestionPreparation.withInterestLabels(measurements([base.id: ["music"]]), verified)
        #expect(labelled.searchLabels[base.id] == ["interest:Photography", "music"])
        let served = InterestMatch.interests(for: ["Photography"], kind: .other, indoor: true,
                                             searchLabels: labelled.searchLabels[base.id] ?? [])
        #expect(served == ["Photography"])
    }

    @Test func suggestionsWithoutInterestsLeaveTheLabelsAlone() throws {
        let base = try #require(try fixtureFacts().places.values.first)
        let oldStyle = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Old research")
        let verified = VerifiedResearch(result: ResearchResult(findings: [], suggestedPlaces: [oldStyle],
                                                               searchNotes: ""), places: [base])
        let before = measurements([base.id: ["music"]])
        #expect(SuggestionPreparation.withInterestLabels(before, verified).searchLabels == before.searchLabels)
    }

    @Test func preparingWithoutNewPlacesStillLabelsThem() async throws {
        let facts = try fixtureFacts()
        let base = try #require(facts.places.values.first)
        let suggestion = SuggestedPlace(name: base.name, area: "", kind: base.kind, why: "Good light",
                                        interests: ["Photography"])
        let verified = VerifiedResearch(result: ResearchResult(findings: [], suggestedPlaces: [suggestion],
                                                               searchNotes: ""), places: [base])
        let service = SuggestionPreparation(fetcher: CappedFetcher(inner: StubFetcher(body: "{}"), limit: 10),
                                            key: "test-key-not-real", facts: facts, record: SourceRecord { _ in })
        let (prepared, labelled) = try await service.prepare(verified, facts: facts,
                                                             measurements: measurements([:]))
        #expect(prepared.places == facts.places)
        #expect(labelled.searchLabels[base.id] == ["interest:Photography"])
    }
}
