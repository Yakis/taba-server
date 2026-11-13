import Foundation
import GuideKit
@testable import LivePipelineKit
import PipelineKit
import ResponsesKit
import Testing

struct ReplayMeasurementsTests {
    private func tripFacts() throws -> TripFacts {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
        return TripFacts(trip: guide.trip, bookings: [], stay: guide.stay, places: guide.places,
                         practical: [], sources: [])
    }

    /// A recorded sources event. `searchLabels` is included only when given, as older evidence lacks it.
    private func event(searchLabels: String?) throws -> [String: JSONValue] {
        var json = "{\"areas\":{\"p\":\"a\"},\"areaLabels\":{\"p\":\"Old Town\"},\"stayWalks\":{\"p\":3},"
            + "\"areaWalks\":{},\"arrivalWalkMinutes\":5,\"departureWalkMinutes\":6,"
            + "\"arrivalMarginMinutes\":0,\"departureMarginMinutes\":30"
        if let searchLabels { json += ",\"searchLabels\":\(searchLabels)" }
        json += "}"
        return try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    @Test func recordedSearchLabelsAreRestoredAndOldEvidenceGivesNone() throws {
        let facts = try tripFacts()
        let recorded = try measurements(event(searchLabels: "{\"p\":[\"music\"]}"), fallback: nil, facts: facts)
        #expect(recorded.searchLabels == ["p": ["music"]])
        let old = try measurements(event(searchLabels: nil), fallback: nil, facts: facts)
        #expect(old.searchLabels.isEmpty)
        #expect(old.areas == ["p": "a"])
        #expect(old.walkFromBase == ["p": 3])
    }

    @Test func suggestionEvidenceWithoutLabelsKeepsTheFallbacksLabels() throws {
        let facts = try tripFacts()
        let before = PipelineInputMeasurements(areas: ["p": "a"], walkFromBase: ["p": 3],
                                               areaWalkMinutes: .object([:]), arrivalWalkMinutes: 5,
                                               departureWalkMinutes: 6, searchLabels: ["p": ["parks"]])
        let after = try measurements(event(searchLabels: nil), fallback: before, facts: facts)
        #expect(after.searchLabels == ["p": ["parks"]])
    }
}
