import Foundation
import GuideKit
import ServerKit
import Testing

struct TripBuildInputTests {
    private let start = LocalDate("2025-11-23")!
    private let end = LocalDate("2025-11-25")!

    @Test func acceptsTypedInputAndRoundTrips() throws {
        let input = try TripBuildInput(destination: "Edinburgh", from: start, to: end, stay: "A hotel")
        let decoded = try JSONDecoder().decode(TripBuildInput.self, from: JSONEncoder().encode(input))
        #expect(decoded.destination == "Edinburgh")
        #expect(decoded.from == start)
        #expect(decoded.to == end)
        #expect(decoded.stay == "A hotel")
    }

    @Test func rejectsLongOrInvalidRanges() throws {
        #expect(throws: TripBuildInput.ValidationError.invalidDates) {
            try TripBuildInput(destination: "Edinburgh", from: end, to: start)
        }
        #expect(throws: TripBuildInput.ValidationError.invalidDates) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: #require(start.adding(days: 14)))
        }
        _ = try TripBuildInput(destination: "Edinburgh", from: start, to: #require(start.adding(days: 13)))
    }

    @Test func rejectsUnknownFieldsAndInvalidNames() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25", "#
            + #""providerURL":"https://example.com"}"#
        #expect(throws: TripBuildInput.ValidationError.unknownField) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
        #expect(throws: TripBuildInput.ValidationError.invalidDestination) {
            try TripBuildInput(destination: "  ", from: start, to: end)
        }
        #expect(throws: TripBuildInput.ValidationError.invalidStay) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, stay: "Line\nBreak")
        }
    }

    @Test func decodesEveryPreferenceAndKeepsInterestOrder() throws {
        let json = #"""
        {"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","stay":"A hotel",
         "pace":"relaxed","interests":["Food","Museums","Parks"],"dailySpend":"high",
         "adults":2,"children":1,"mobilityNotes":["Step-free access"]}
        """#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.pace == .relaxed)
        #expect(input.interests == ["Food", "Museums", "Parks"])
        #expect(input.dailySpend == .high)
        #expect(input.adults == 2)
        #expect(input.children == 1)
        #expect(input.mobilityNotes == ["Step-free access"])
    }

    @Test func oldBodyDecodesWithoutPreferences() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25"}"#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.pace == nil)
        #expect(input.interests == nil)
        #expect(input.dailySpend == nil)
        #expect(input.adults == nil)
        #expect(input.children == nil)
        #expect(input.mobilityNotes == nil)
    }

    @Test func preferencesRoundTrip() throws {
        let input = try TripBuildInput(destination: "Edinburgh", from: start, to: end, pace: .packed,
                                       interests: ["Food", "Parks"], dailySpend: .low, adults: 3, children: 0,
                                       mobilityNotes: ["Avoid stairs"])
        let decoded = try JSONDecoder().decode(TripBuildInput.self, from: JSONEncoder().encode(input))
        #expect(decoded.pace == .packed)
        #expect(decoded.interests == ["Food", "Parks"])
        #expect(decoded.dailySpend == .low)
        #expect(decoded.adults == 3)
        #expect(decoded.children == 0)
        #expect(decoded.mobilityNotes == ["Avoid stairs"])
    }

    @Test func acceptsEmptyAndBoundaryPreferences() throws {
        _ = try TripBuildInput(destination: "Edinburgh", from: start, to: end, interests: [])
        _ = try TripBuildInput(destination: "Edinburgh", from: start, to: end,
                               interests: (1...10).map { "Interest \($0)" }, adults: 10, children: 10,
                               mobilityNotes: (1...5).map { "Note \($0)" })
        _ = try TripBuildInput(destination: "Edinburgh", from: start, to: end,
                               interests: [String(repeating: "a", count: 60)], adults: 1, children: 0,
                               mobilityNotes: [String(repeating: "b", count: 120)])
    }

    @Test func rejectsInvalidInterests() throws {
        func make(_ interests: [String]) throws -> TripBuildInput {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, interests: interests)
        }
        #expect(throws: TripBuildInput.ValidationError.invalidInterests) {
            try make((1...11).map { "Interest \($0)" })
        }
        #expect(throws: TripBuildInput.ValidationError.invalidInterests) { try make([""]) }
        #expect(throws: TripBuildInput.ValidationError.invalidInterests) { try make([" Food"]) }
        #expect(throws: TripBuildInput.ValidationError.invalidInterests) {
            try make([String(repeating: "a", count: 61)])
        }
        #expect(throws: TripBuildInput.ValidationError.invalidInterests) { try make(["Food", "food"]) }
        #expect(throws: TripBuildInput.ValidationError.invalidInterests) { try make(["Line\nBreak"]) }
    }

    @Test func rejectsInvalidParty() throws {
        #expect(throws: TripBuildInput.ValidationError.invalidParty) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, adults: 0)
        }
        #expect(throws: TripBuildInput.ValidationError.invalidParty) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, adults: 11)
        }
        #expect(throws: TripBuildInput.ValidationError.invalidParty) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, children: -1)
        }
        #expect(throws: TripBuildInput.ValidationError.invalidParty) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, children: 11)
        }
    }

    @Test func rejectsInvalidMobilityNotes() throws {
        #expect(throws: TripBuildInput.ValidationError.invalidMobility) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end,
                               mobilityNotes: (1...6).map { "Note \($0)" })
        }
        #expect(throws: TripBuildInput.ValidationError.invalidMobility) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end,
                               mobilityNotes: [String(repeating: "b", count: 121)])
        }
    }

    @Test func rejectsUnknownPaceInJSON() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","pace":"fast"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
    }

    @Test func rejectsPreferencesTogetherWithFacts() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let fixture = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: fixtureURL))
        func make(pace: Pace? = nil, interests: [String]? = nil, dailySpend: DailySpend? = nil,
                  adults: Int? = nil, children: Int? = nil, mobilityNotes: [String]? = nil) throws {
            _ = try TripBuildInput(destination: fixture.trip.destination.name, from: fixture.trip.dates.start,
                                   to: fixture.trip.dates.end, facts: fixture, pace: pace, interests: interests,
                                   dailySpend: dailySpend, adults: adults, children: children,
                                   mobilityNotes: mobilityNotes)
        }
        // A facts seed alone is still fine.
        try make()
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) { try make(pace: .packed) }
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) { try make(interests: []) }
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) { try make(dailySpend: .low) }
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) { try make(adults: 1) }
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) { try make(children: 0) }
        #expect(throws: TripBuildInput.ValidationError.preferencesWithFacts) { try make(mobilityNotes: []) }
    }

    @Test func resolvingTheModelRecordsTheDefaultOnlyWhenTheTripNamesNone() throws {
        let plain = try TripBuildInput(destination: "Edinburgh", from: start, to: end)
        #expect(plain.resolvingModel("gpt-6.1-sol").model == "gpt-6.1-sol")
        let named = try TripBuildInput(destination: "Edinburgh", from: start, to: end, model: "gpt-6.1-terra")
        #expect(named.resolvingModel("gpt-6.1-sol").model == "gpt-6.1-terra")
        #expect(plain.resolvingModel("gpt-6-astra").model == nil)
    }
}
