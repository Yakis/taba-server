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
}
