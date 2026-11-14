import Foundation
import GuideKit
@testable import PipelineKit
import Testing

struct ResearchFactFilterTests {
    /// A visited place from the Edinburgh fixture, a plan that visits it, and the trip's other facts.
    private struct Setting {
        let base: TripFacts
        let draft: PlanDraft
        let visitedName: String
    }

    private func setting() throws -> Setting {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
        let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
        let placeId = try #require(guide.places.keys.sorted().first)
        let visitedName = try #require(guide.places[placeId]?.name)
        let day = guide.trip.dates.start
        let stop = PlanDraftStop(id: "d1-s1", placeId: placeId, kind: .sight, mealSlot: nil,
                                 start: try #require(LocalTime("10:00")), minutes: 60, flexible: false,
                                 alternative: nil, reason: "Visit", findingIds: [])
        let draft = PlanDraft(days: [PlanDraftDay(date: day, theme: "Walk", stops: [stop])], lists: [],
                              skippedMeals: [], openQuestions: [], changes: [])
        let assumptions = Source(id: "taba-assumptions", url: "https://example.com/assumptions",
                                 title: "Assumptions", checkedAt: day)
        let practical = [Fact(text: "Bring a layer.", sourceId: "taba-assumptions", checkedAt: day),
                         Fact(text: "Do not schedule the walk.", sourceId: "taba-assumptions", checkedAt: day)]
        let base = TripFacts(trip: guide.trip, bookings: [], stay: guide.stay, places: guide.places,
                             practical: practical, sources: [assumptions])
        return Setting(base: base, draft: draft, visitedName: visitedName)
    }

    private func finding(_ id: String, kind: FindingKind = .event, title: String = "Late opening",
                         summary: String = "Open late on the day.", placeName: String?,
                         onTripDates: Bool = true) -> ResearchFinding {
        ResearchFinding(id: id, kind: kind, title: title, summary: summary, startDate: nil, endDate: nil,
                        times: nil, placeName: placeName, address: nil, url: "https://example.com/\(id)",
                        sourceTitle: "Example", confidence: .high, onTripDates: onTripDates)
    }

    /// The facts as the pipeline makes them: one research fact and source for each finding, in order.
    private func withResearch(_ base: TripFacts, _ findings: [ResearchFinding]) -> TripFacts {
        var sources = base.sources
        var practical = base.practical
        let checked = base.trip.dates.start
        for (index, finding) in findings.enumerated() {
            let id = "taba-research-\(index)"
            sources.append(Source(id: id, url: finding.url, title: finding.sourceTitle, checkedAt: checked))
            practical.append(Fact(text: ResearchFactFilter.factText(for: finding), sourceId: id, checkedAt: checked))
        }
        return TripFacts(trip: base.trip, bookings: base.bookings, stay: base.stay, places: base.places,
                         practical: practical, sources: sources)
    }

    private func filtered(_ findings: [ResearchFinding]) throws -> TripFacts {
        let setting = try setting()
        return ResearchFactFilter.filtered(withResearch(setting.base, findings), findings: findings,
                                           draft: setting.draft)
    }

    private func texts(_ facts: TripFacts) -> [String] {
        facts.practical.map(\.text)
    }

    @Test func keepsATransportWarningOnTheTripDates() throws {
        let warning = finding("f1", kind: .transport, title: "Engineering works", summary: "Trains run late.",
                              placeName: nil)
        let result = try filtered([warning])
        #expect(texts(result).contains(ResearchFactFilter.factText(for: warning)))
    }

    @Test func keepsAnEventAtAVisitedPlace() throws {
        let visited = try setting().visitedName
        let event = finding("f1", placeName: visited)
        #expect(texts(try filtered([event])).contains(ResearchFactFilter.factText(for: event)))
    }

    @Test func keepsAnEventWhoseTitleNamesAVisitedPlaceWhenThePlaceNameIsEmpty() throws {
        let visited = try setting().visitedName
        let event = finding("f1", title: "Stalls at \(visited)", placeName: "  ")
        #expect(texts(try filtered([event])).contains(ResearchFactFilter.factText(for: event)))
    }

    @Test func dropsAnEventAtAPlaceThePlanDoesNotVisit() throws {
        let event = finding("f1", placeName: "Quayside Pop-up Hall")
        #expect(!texts(try filtered([event])).contains(ResearchFactFilter.factText(for: event)))
    }

    @Test func dropsAFindingOffTheTripDates() throws {
        let visited = try setting().visitedName
        let event = finding("f1", kind: .market, placeName: visited, onTripDates: false)
        let result = try filtered([event])
        #expect(!texts(result).contains(ResearchFactFilter.factText(for: event)))
        #expect(!result.sources.contains { $0.id == "taba-research-0" })
    }

    @Test func dropsAFactThatInstructsThePlanner() throws {
        let visited = try setting().visitedName
        let instruction = finding("f1", summary: "Do not schedule the stalls for 14 November.", placeName: visited)
        #expect(!texts(try filtered([instruction])).contains(ResearchFactFilter.factText(for: instruction)))
    }

    @Test func alwaysKeepsFactsThatDidNotComeFromResearch() throws {
        let result = try filtered([])
        #expect(texts(result) == ["Bring a layer.", "Do not schedule the walk."])
        #expect(result.sources.map(\.id) == ["taba-assumptions"])
    }

    @Test(arguments: ["Do not schedule the stalls for 14 November.", "Good for the traveller's afternoon.",
                      "Add it to the itinerary.", "An outlying alternative, not a walking stop.",
                      "Don't include it in the day.", "Don\u{2019}t plan a visit on Monday.",
                      "Avoid scheduling it after dark."])
    func plannerInstructionsAreRecognised(text: String) {
        #expect(ResearchFactFilter.readsAsInstruction(text))
    }

    @Test(arguments: ["Stalls open 10:00 to 16:00 on Sundays.", "Engineering works close the platform on Saturday.",
                      "Tickets cost five pounds and need booking.", "The Christmas stalls are scheduled for Saturday.",
                      "Scheduled engineering works close the platform."])
    func factsForTheTravellerAreKept(text: String) {
        #expect(!ResearchFactFilter.readsAsInstruction(text))
    }
}
