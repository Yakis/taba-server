import BuildKit
import Foundation
import GuideKit
import SourcesKit
import Testing

/// Fails any request, so the test proves that no geocoder lookup happens without a stay.
private actor RefusingFetcher: HTTPFetching {
    private(set) var count = 0
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        count += 1
        throw URLError(.notConnectedToInternet)
    }
}

@Test func standardPreferencesAreTodaysDefaults() {
    let standard = TripPreferences.standard
    #expect(standard.pace == .unhurried)
    #expect(standard.interests.isEmpty)
    #expect(standard.dailySpend == .moderate)
    #expect(standard.adults == 1)
    #expect(standard.children == 0)
    #expect(standard.mobilityNotes.isEmpty)
    #expect(standard.party == Party(adults: 1, children: 0, mobilityNotes: []))
}

@Test func baseFactsUsesTheGivenPreferences() async throws {
    let start = try #require(LocalDate("2025-11-23"))
    let end = try #require(LocalDate("2025-11-25"))
    let preferences = TripPreferences(pace: .packed, interests: ["Food", "Museums"], dailySpend: .high,
                                      adults: 2, children: 1, mobilityNotes: ["Step-free access"])
    let options = SourceInput(destination: "Edinburgh", from: start, to: end, preferences: preferences)
    let centre = try #require(Coordinate(latitude: 55.95, longitude: -3.19))
    let fetcher = RefusingFetcher()
    let facts = try await SourcePreparation.baseFacts(options, seed: nil, centre: centre, country: "GB",
        timeZone: "Europe/London", geocoder: NominatimGeocoder(fetcher: fetcher))
    #expect(facts.trip.pace == .packed)
    #expect(facts.trip.interests == ["Food", "Museums"])
    #expect(facts.trip.budget.dailySpend == .high)
    #expect(facts.trip.party == Party(adults: 2, children: 1, mobilityNotes: ["Step-free access"]))
    #expect(facts.trip.budget.currencyCode == "GBP")
    #expect(await fetcher.count < 1)
}

@Test func baseFactsWithStandardPreferencesKeepsTheOldScaffold() async throws {
    let start = try #require(LocalDate("2025-11-23"))
    let end = try #require(LocalDate("2025-11-25"))
    let options = SourceInput(destination: "Edinburgh", from: start, to: end)
    let centre = try #require(Coordinate(latitude: 55.95, longitude: -3.19))
    let facts = try await SourcePreparation.baseFacts(options, seed: nil, centre: centre, country: "GB",
        timeZone: "Europe/London", geocoder: NominatimGeocoder(fetcher: RefusingFetcher()))
    #expect(facts.trip.party == Party(adults: 1, children: 0, mobilityNotes: []))
    #expect(facts.trip.budget.dailySpend == .moderate)
    #expect(facts.trip.interests.isEmpty)
    #expect(facts.trip.pace == .unhurried)
    #expect(facts.trip.voice == "Warm, practical and concise")
}
