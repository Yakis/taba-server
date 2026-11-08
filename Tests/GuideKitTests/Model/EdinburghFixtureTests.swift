import Foundation
import GuideKit
import Testing

struct EdinburghFixtureTests {
    private func loadGuide() throws -> Guide {
        try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
    }

    @Test func fixtureHasNoStructureProblems() throws {
        let guide = try loadGuide()
        #expect(guide.structureProblems.isEmpty)
        try guide.validateStructure()
    }

    @Test func tripStartsOnASunday() throws {
        let guide = try loadGuide()
        #expect(guide.trip.dates.start == LocalDate("2025-11-23"))
        #expect(guide.trip.dates.start.weekday == .sunday)
    }

    @Test func tripHasThreeDays() throws {
        let guide = try loadGuide()
        #expect(guide.days.count == 3)
        #expect(guide.places.count == 21)
    }

    @Test func fixtureRoundTripsByteForByte() throws {
        let original = try Fixture.edinburghMockData()
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: original)
        let encoded = try GuideKit.jsonEncoder().encode(guide)
        #expect(encoded == original)
    }
}
