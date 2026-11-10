import Foundation
import GuideKit
import ServerKit
import Testing

struct TripBuildInputLuggageTests {
    private let start = LocalDate("2025-11-23")!
    private let end = LocalDate("2025-11-25")!

    @Test func decodesAndRoundTripsLuggage() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","#
            + #""luggage":"Station Left Luggage"}"#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.luggage == "Station Left Luggage")
        let decoded = try JSONDecoder().decode(TripBuildInput.self, from: JSONEncoder().encode(input))
        #expect(decoded.luggage == "Station Left Luggage")
        let plain = try JSONDecoder().decode(TripBuildInput.self, from: Data(
            #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25"}"#.utf8))
        #expect(plain.luggage == nil)
    }

    @Test func rejectsInvalidLuggage() throws {
        func make(_ luggage: String) throws -> TripBuildInput {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, luggage: luggage)
        }
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) { try make("") }
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) { try make(" Station") }
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) { try make("Station ") }
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) { try make("Line\nBreak") }
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) {
            try make(String(repeating: "a", count: 121))
        }
        _ = try make(String(repeating: "a", count: 120))
    }

    @Test func rejectsInvalidLuggageInJSON() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","luggage":""}"#
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
    }

    @Test func rejectsUnknownKeysNextToLuggage() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","luggage":"Station", "#
            + #""luggageURL":"https://example.com"}"#
        #expect(throws: TripBuildInput.ValidationError.unknownField) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
    }

    @Test func resolvingTheModelKeepsLuggage() throws {
        let input = try TripBuildInput(destination: "Edinburgh", from: start, to: end,
                                       luggage: "Station Left Luggage")
        #expect(input.resolvingModel("gpt-6.1-sol").luggage == "Station Left Luggage")
    }

    @Test func luggageCountsAsAPreferenceWithFacts() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let fixture = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: fixtureURL))
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) {
            try TripBuildInput(destination: fixture.trip.destination.name, from: fixture.trip.dates.start,
                               to: fixture.trip.dates.end, facts: fixture, luggage: "Station Left Luggage")
        }
    }

    @Test func decodesHandLuggageOnly() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","handLuggageOnly":true}"#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.handLuggageOnly == true)
        #expect(input.luggage == nil)
        let decoded = try JSONDecoder().decode(TripBuildInput.self, from: JSONEncoder().encode(input))
        #expect(decoded.handLuggageOnly == true)
        #expect(input.resolvingModel("gpt-6.1-sol").handLuggageOnly == true)
    }

    @Test func handLuggageOnlyFalseIsTheSameAsNotSaid() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","handLuggageOnly":false}"#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.handLuggageOnly == nil)
        let plain = try JSONDecoder().decode(TripBuildInput.self, from: Data(
            #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25"}"#.utf8))
        #expect(plain.handLuggageOnly == nil)
    }

    @Test func rejectsHandLuggageOnlyWithLuggage() throws {
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, luggage: "Station Left Luggage",
                               handLuggageOnly: true)
        }
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","#
            + #""luggage":"Station Left Luggage","handLuggageOnly":true}"#
        #expect(throws: TripBuildInput.ValidationError.invalidLuggage) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
        _ = try TripBuildInput(destination: "Edinburgh", from: start, to: end, luggage: "Station Left Luggage",
                               handLuggageOnly: false)
    }

    @Test func handLuggageOnlyCountsAsAPreferenceWithFacts() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let fixture = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: fixtureURL))
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) {
            try TripBuildInput(destination: fixture.trip.destination.name, from: fixture.trip.dates.start,
                               to: fixture.trip.dates.end, facts: fixture, handLuggageOnly: true)
        }
    }
}
