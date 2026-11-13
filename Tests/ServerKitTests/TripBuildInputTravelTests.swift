import Foundation
import GuideKit
import ServerKit
import Testing

struct TripBuildInputTravelTests {
    private let start = LocalDate("2026-11-14")!
    private let end = LocalDate("2026-11-14")!

    @Test func decodesTravelWithAndWithoutPlace() throws {
        let json = #"{"destination":"Leeds","from":"2026-11-14","to":"2026-11-14","#
            + #""travel":{"mode":"train","place":"Leeds station"}}"#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.travel == TripTravelInput(mode: .train, place: "Leeds station"))
        let decoded = try JSONDecoder().decode(TripBuildInput.self, from: JSONEncoder().encode(input))
        #expect(decoded.travel == input.travel)
        #expect(input.resolvingModel("gpt-6.1-sol").travel == input.travel)

        let bare = try JSONDecoder().decode(TripBuildInput.self, from: Data(
            #"{"destination":"Leeds","from":"2026-11-14","to":"2026-11-14","travel":{"mode":"car"}}"#.utf8))
        #expect(bare.travel == TripTravelInput(mode: .car, place: nil))
    }

    @Test func travelIsOptionalAndNullIsNotSaid() throws {
        let plain = try JSONDecoder().decode(TripBuildInput.self, from: Data(
            #"{"destination":"Leeds","from":"2026-11-14","to":"2026-11-14"}"#.utf8))
        #expect(plain.travel == nil)
        let null = try JSONDecoder().decode(TripBuildInput.self, from: Data(
            #"{"destination":"Leeds","from":"2026-11-14","to":"2026-11-14","travel":null}"#.utf8))
        #expect(null.travel == nil)
    }

    @Test func rejectsUnknownKeysInsideTravel() {
        let json = #"{"destination":"Leeds","from":"2026-11-14","to":"2026-11-14","#
            + #""travel":{"mode":"train","time":"10:00"}}"#
        #expect(throws: TripBuildInput.ValidationError.unknownField) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
    }

    @Test func rejectsAnUnknownMode() {
        let json = #"{"destination":"Leeds","from":"2026-11-14","to":"2026-11-14","travel":{"mode":"bike"}}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
    }

    @Test func rejectsAnInvalidTravelPlace() throws {
        func make(_ place: String) throws -> TripBuildInput {
            try TripBuildInput(destination: "Leeds", from: start, to: end,
                               travel: TripTravelInput(mode: .train, place: place))
        }
        #expect(throws: TripBuildInput.ValidationError.invalidTravel) { try make("") }
        #expect(throws: TripBuildInput.ValidationError.invalidTravel) { try make(" Leeds station") }
        #expect(throws: TripBuildInput.ValidationError.invalidTravel) { try make("Leeds\nstation") }
        _ = try make("Leeds station")
    }

    @Test func travelCountsAsAPreferenceWithFacts() throws {
        let json = #"{"destination":"Leeds","from":"2026-11-14","to":"2026-11-14","travel":{"mode":"flight"}}"#
        let decoded = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(decoded.travel?.mode == .flight)
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let fixture = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: fixtureURL))
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) {
            try TripBuildInput(destination: fixture.trip.destination.name, from: fixture.trip.dates.start,
                               to: fixture.trip.dates.end, facts: fixture,
                               travel: TripTravelInput(mode: .train))
        }
    }
}
