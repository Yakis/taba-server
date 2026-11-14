import Foundation
import GuideKit
import Testing

struct EdinburghAssemblyTests {
    private struct Assembled {
        let fixture: Guide
        let result: AssemblyResult
    }

    private func assembleFixture() throws -> Assembled {
        let fixture = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
        let facts = TripFacts(
            trip: fixture.trip,
            bookings: fixture.bookings,
            stay: fixture.stay,
            places: fixture.places,
            practical: fixture.practical,
            sources: fixture.sources
        )
        let result = GuideAssembler(walkTimes: StraightLineWalkTimes()).assemble(
            id: fixture.id,
            facts: facts,
            draft: FixtureDraft.planDraft(from: fixture),
            copy: FixtureDraft.copy(from: fixture)
        )
        return Assembled(fixture: fixture, result: result)
    }

    /// A stop with its id and walk leg cleared, so two stops can be compared on their facts alone.
    private func withoutIdentity(_ stop: Stop) -> Stop {
        Stop(
            id: "",
            kind: stop.kind,
            mealSlot: stop.mealSlot,
            placeId: stop.placeId,
            start: stop.start,
            minutes: stop.minutes,
            flexible: stop.flexible,
            alternative: stop.alternative,
            copy: stop.copy,
            legFromPrevious: nil
        )
    }

    @Test func daysKeepTheFixtureDatesAndCopy() throws {
        let assembled = try assembleFixture()
        #expect(assembled.result.guide.days.map(\.date) == assembled.fixture.days.map(\.date))
        #expect(assembled.result.guide.days.map(\.copy) == assembled.fixture.days.map(\.copy))
    }

    @Test func stopsKeepTheFixtureTimesPlacesAndCopy() throws {
        let assembled = try assembleFixture()
        for (guideDay, fixtureDay) in zip(assembled.result.guide.days, assembled.fixture.days) {
            #expect(guideDay.stops.map(withoutIdentity) == fixtureDay.stops.map(withoutIdentity))
        }
    }

    @Test func stopsAreRenumberedInTimeOrderAndMapped() throws {
        let assembled = try assembleFixture()
        for (dayIndex, pair) in zip(assembled.result.guide.days, assembled.fixture.days).enumerated() {
            let (guideDay, fixtureDay) = pair
            for (position, stop) in fixtureDay.stops.enumerated() {
                let expected = "d\(dayIndex + 1)-s\(position + 1)"
                #expect(assembled.result.stopIds[stop.id] == expected)
                #expect(guideDay.stops[position].id == expected)
            }
        }
    }

    /// A pick list without its plan key, so it can be compared with the fixture's list, which has none.
    private func withoutKey(_ list: PlaceList) -> PlaceList {
        PlaceList(title: list.title, caption: list.caption, placeIds: list.placeIds)
    }

    @Test func placesAndListsMatchTheFixture() throws {
        let assembled = try assembleFixture()
        #expect(assembled.result.guide.places == assembled.fixture.places)
        #expect(assembled.result.guide.lists.map(withoutKey) == assembled.fixture.lists)
        #expect(assembled.result.guide.lists.map(\.key) == [.eat, .drink, .photos, .groceries])
        #expect(assembled.result.guide.tasting == assembled.fixture.tasting)
    }

    @Test func stayAndLuggageNeedNoCopySoNothingIsMissing() throws {
        let assembled = try assembleFixture()
        #expect(assembled.result.problems.isEmpty, "\(assembled.result.problems)")
        #expect(assembled.result.guide.places["manual:stay-new-town"]?.copy == nil)
        #expect(assembled.result.guide.places["manual:luggage-rose"]?.copy == nil)
    }

    @Test func assembledGuideHasNoStructureProblems() throws {
        let assembled = try assembleFixture()
        try assembled.result.guide.validateStructure()
    }

    @Test func checkerReportsTheSameIssuesAsTheFixture() throws {
        let assembled = try assembleFixture()
        let fixtureIssues = Plan.issues(assembled.fixture)
        let expected = fixtureIssues.map { issue in
            PlanIssue(
                severity: issue.severity,
                kind: issue.kind,
                date: issue.date,
                stopId: issue.stopId.flatMap { assembled.result.stopIds[$0] },
                message: issue.message
            )
        }
        // Ten: the new rest check flags 24 November, a full day with no rest stop (plan.md rule 10).
        #expect(fixtureIssues.count == 10)
        #expect(Plan.issues(assembled.result.guide) == expected)
    }

    @Test func walkingLegsAreMeasuredBetweenConsecutivePlaces() throws {
        let assembled = try assembleFixture()
        let days = assembled.result.guide.days
        #expect(days[0].stops[0].legFromPrevious == nil)
        #expect(days[0].stops[1].legFromPrevious != nil)
        // In day three, "d3-quick-bite" has no place, so neither it nor the stop after it gets a leg.
        let dayThree = days[2].stops
        #expect(dayThree[3].legFromPrevious == nil)
        #expect(dayThree[4].legFromPrevious == nil)
        // Both train stops are at the same station, so the walk between them is the minimum of one minute.
        #expect(dayThree[5].legFromPrevious?.minutes == 1)
    }

    @Test func assembledGuideIsADraftAtVersionOne() throws {
        let assembled = try assembleFixture()
        #expect(assembled.result.guide.status == .draft)
        #expect(assembled.result.guide.version == 1)
    }
}
