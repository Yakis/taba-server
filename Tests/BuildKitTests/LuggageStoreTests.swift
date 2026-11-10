import BuildKit
import Foundation
import GuideKit
import SourcesKit
import Testing

/// Answers Nominatim searches from a table, so the tests never reach the network.
private actor NominatimFake: HTTPFetching {
    private(set) var queries: [String] = []
    private let answers: [String: String]

    init(answers: [String: String]) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = request.url?.absoluteString ?? ""
        queries.append(url)
        let body = answers.first { url.contains($0.key) }?.value ?? "[]"
        return HTTPResponse(status: 200, body: Data(body.utf8), headers: [:])
    }
}

private let luggageHit = #"""
[{"lat":"55.9533","lon":"-3.1883","display_name":"Station Left Luggage, Example Street, Edinburgh",
  "address":{"country_code":"gb"}}]
"""#

private let assumedHours = "Luggage store hours 08:00 to 20:00 are an assumption, not confirmed. "
    + "Check them before relying on it."
private let notFound = "The luggage store could not be found on the map, so the plan carries the bags. "
    + "Check where bags can be left."

private func basics(luggage: String?, fetcher: NominatimFake) async throws -> TripFacts {
    let start = try #require(LocalDate("2025-11-23"))
    let end = try #require(LocalDate("2025-11-25"))
    let options = SourceInput(destination: "Edinburgh", from: start, to: end, luggage: luggage)
    let centre = try #require(Coordinate(latitude: 55.95, longitude: -3.19))
    return try await SourcePreparation.baseFacts(options, seed: nil, centre: centre, country: "GB",
        timeZone: "Europe/London", geocoder: NominatimGeocoder(fetcher: fetcher, interval: .zero))
}

@Test func foundLuggageStoreIsPlacedAndGivenAssumedHours() async throws {
    let fetcher = NominatimFake(answers: ["Station": luggageHit])
    let facts = try await basics(luggage: "Station Left Luggage", fetcher: fetcher)
    let place = try #require(facts.places["manual:luggage"])
    #expect(place.name == "Station Left Luggage")
    #expect(place.kind == .luggage)
    #expect(place.location.approximate == false)
    #expect(place.location.address == "Station Left Luggage, Example Street, Edinburgh")
    #expect(place.location.coordinate.latitude == 55.9533)
    #expect(place.location.coordinate.longitude == -3.1883)
    #expect(place.hours.hoursKnown == false)
    #expect(place.priceLevel == nil)
    #expect(place.booking == PlaceBooking(needed: false, url: nil))
    #expect(place.indoor)
    #expect(place.images.isEmpty && place.facts.isEmpty && place.copy == nil)
    #expect(facts.places.count == 2)
    #expect(facts.stay.placeId == "manual:stay")
    let slot = LuggageSlot(placeId: "manual:luggage", opens: try #require(LocalTime("08:00")),
                           closes: try #require(LocalTime("20:00")))
    #expect(facts.stay.luggage == slot)
    #expect(await fetcher.queries.count == 1)
}

@Test func luggageNameThatIsNotFoundGivesNoPlaceAndNoError() async throws {
    let fetcher = NominatimFake(answers: [:])
    let facts = try await basics(luggage: "Nowhere Left Luggage", fetcher: fetcher)
    #expect(facts.places["manual:luggage"] == nil)
    #expect(facts.places.count == 1)
    #expect(facts.stay.luggage == nil)
    #expect(await fetcher.queries.count == 1)
}

@Test func noLuggageNameLeavesThePlanAsBefore() async throws {
    let fetcher = NominatimFake(answers: ["Station": luggageHit])
    let facts = try await basics(luggage: nil, fetcher: fetcher)
    #expect(facts.places.count == 1)
    #expect(facts.stay.luggage == nil)
    #expect(await fetcher.queries.isEmpty)
}

@Test func foundLuggageAddsTheAssumptionFact() throws {
    let start = try #require(LocalDate("2025-11-23"))
    let end = try #require(LocalDate("2025-11-25"))
    let options = SourceInput(destination: "Edinburgh", from: start, to: end, luggage: "Station Left Luggage")
    var sources: [Source] = []
    let facts = SourcePreparation.assumptions(options, seed: nil, country: "GB", today: start,
                                              luggageFound: true, sources: &sources)
    #expect(facts.contains { $0.text == assumedHours })
    #expect(!facts.contains { $0.text == notFound })
}

@Test func notFoundLuggageAddsTheCheckFactWithoutTheTypedName() throws {
    let start = try #require(LocalDate("2025-11-23"))
    let end = try #require(LocalDate("2025-11-25"))
    let options = SourceInput(destination: "Edinburgh", from: start, to: end, luggage: "Station Left Luggage")
    var sources: [Source] = []
    let facts = SourcePreparation.assumptions(options, seed: nil, country: "GB", today: start,
                                              luggageFound: false, sources: &sources)
    #expect(facts.contains { $0.text == notFound })
    #expect(!facts.contains { $0.text == assumedHours })
    #expect(!facts.contains { $0.text.contains("Station Left Luggage") })
}

@Test func noLuggageNameAddsNoLuggageFact() throws {
    let start = try #require(LocalDate("2025-11-23"))
    let end = try #require(LocalDate("2025-11-25"))
    let options = SourceInput(destination: "Edinburgh", from: start, to: end)
    var sources: [Source] = []
    let facts = SourcePreparation.assumptions(options, seed: nil, country: "GB", today: start,
                                              luggageFound: false, sources: &sources)
    #expect(facts.count == 2)
    #expect(!facts.contains { $0.text.contains("uggage") })
}
