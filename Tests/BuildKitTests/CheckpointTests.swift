import BuildKit
import Foundation
import GuideKit
import Testing

@Test func basicsCheckpointRoundTripsInlineFacts() throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("GuideKitTests/Fixtures/edinburgh-mock.json")
    let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: fixture))
    let facts = TripFacts(trip: guide.trip, bookings: guide.bookings, stay: guide.stay, places: guide.places,
                          practical: guide.practical, sources: guide.sources)
    let checkpoint = BasicsCheckpoint(facts: facts, weather: [], today: guide.trip.dates.start)
    let restored = try JSONDecoder().decode(BasicsCheckpoint.self, from: JSONEncoder().encode(checkpoint))
    #expect(restored.facts.value == facts)
    #expect(restored.weather.isEmpty)
    #expect(restored.today == guide.trip.dates.start)
}
