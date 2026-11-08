import Foundation
import GuideKit
import Testing

struct EdinburghPlanTests {
    private func loadGuide() throws -> Guide {
        try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
    }

    @Test func checkerFlagsTheSundayWithoutDinner() throws {
        let issues = Plan.issues(try loadGuide())
        #expect(issues.contains(where: {
            $0.kind == .mealMissing && $0.date == LocalDate("2025-11-23") && $0.message.contains("dinner")
        }))
    }

    @Test func checkerFlagsTheMondayWithoutBreakfast() throws {
        let issues = Plan.issues(try loadGuide())
        #expect(issues.contains(where: {
            $0.kind == .mealMissing && $0.date == LocalDate("2025-11-24") && $0.message.contains("breakfast")
        }))
    }

    @Test func issuesAreSortedByDateThenStart() throws {
        let issues = Plan.issues(try loadGuide())
        #expect(issues.map(\.date) == issues.map(\.date).sorted())
    }
}
