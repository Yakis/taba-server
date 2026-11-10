import Foundation
import GuideKit
import Testing

/// A place used by more than one stop on the trip.
struct RepeatCheckTests {
    private func cafe(_ id: String = "cafe", name: String = "Test Cafe") -> Place {
        Plan.place(id, name: name, hours: Plan.alwaysOpen)
    }

    /// A stop of 45 minutes at a place, by default a breakfast at the cafe.
    private func stop(_ id: String, at start: Int, _ place: String = "cafe", kind: StopKind = .meal) -> Stop {
        Plan.stop(
            id,
            start: start,
            minutes: 45,
            place: place,
            kind: kind,
            meal: kind == .meal ? .breakfast : nil,
            flexible: true
        )
    }

    private func repeats(_ issues: [PlanIssue]) -> [PlanIssue] {
        issues.filter { $0.kind == .placeRepeated }
    }

    @Test func sameCafeForBreakfastOnTwoDaysWarnsOnTheSecondDay() {
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [stop("first", at: 480)]),
            SampleGuide.day(on: "2026-11-23", stops: [stop("second", at: 480)])
        ]
        let found = repeats(Plan.issues(Plan.guide(days: days, places: [cafe()])))
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.date == SampleGuide.date("2026-11-23"))
        #expect(found.first?.stopId == "second")
        #expect(found.first?.message == "Test Cafe is already used on 2026-11-22 at 08:00. Use a different place here.")
    }

    @Test func threeUsesGiveTwoWarnings() {
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [stop("first", at: 480)]),
            SampleGuide.day(on: "2026-11-23", stops: [stop("second", at: 480)]),
            SampleGuide.day(on: "2026-11-24", stops: [stop("third", at: 480)])
        ]
        let found = repeats(Plan.issues(Plan.guide(days: days, places: [cafe()])))
        #expect(found.map(\.stopId) == ["second", "third"])
        #expect(found.last?.message == "Test Cafe is already used on 2026-11-22 at 08:00. Use a different place here.")
    }

    @Test func backToBackStopsAtOnePlaceAreNotRepeats() {
        // Lunch at the cafe, then browsing it straight after: no warning. A later visit on another day is a repeat
        // of the first use, not of the back-to-back stop.
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [
                stop("lunch", at: 480),
                stop("browse", at: 600, kind: .sight)
            ]),
            SampleGuide.day(on: "2026-11-23", stops: [stop("again", at: 480)])
        ]
        let found = repeats(Plan.issues(Plan.guide(days: days, places: [cafe()])))
        #expect(found.map(\.stopId) == ["again"])
        #expect(found.first?.message == "Test Cafe is already used on 2026-11-22 at 08:00. Use a different place here.")
    }

    @Test func stopsOnTheSameDayThatAreNotBackToBackAreRepeats() {
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [
                stop("first", at: 480),
                stop("market", at: 600, "market", kind: .sight),
                stop("later", at: 720)
            ])
        ]
        let places = [cafe(), Plan.place("market", name: "Test Market", kind: .market)]
        let found = repeats(Plan.issues(Plan.guide(days: days, places: places)))
        #expect(found.map(\.stopId) == ["later"])
    }

    @Test(arguments: [PlaceKind.station, .luggage])
    func stationAndLuggagePlacesAreNotCounted(kind: PlaceKind) {
        let place = Plan.place("place", name: "Test Place", kind: kind, hours: Plan.alwaysOpen)
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [stop("a", at: 480, "place", kind: .sight)]),
            SampleGuide.day(on: "2026-11-23", stops: [stop("b", at: 480, "place", kind: .sight)])
        ]
        #expect(repeats(Plan.issues(Plan.guide(days: days, places: [place]))).isEmpty)
    }

    @Test func theLuggageStoreNamedInTheStayIsNotCounted() {
        let store = Plan.place("store", name: "Test Store", kind: .shop, hours: Plan.alwaysOpen)
        let stay = SampleGuide.stay(placeId: SampleGuide.hotelId, luggagePlaceId: "store")
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [stop("a", at: 480, "store", kind: .sight)]),
            SampleGuide.day(on: "2026-11-23", stops: [stop("b", at: 480, "store", kind: .sight)])
        ]
        let issues = Plan.issues(Plan.guide(days: days, places: [store], stay: stay))
        #expect(repeats(issues).isEmpty)
    }

    @Test func theStayIsNotCounted() {
        // The stay is a cafe here, so only the stay exemption (not the lodging kind) keeps it out of the check.
        let hotel = Plan.place(SampleGuide.hotelId, name: "Test Hotel", kind: .cafe, hours: Plan.alwaysOpen)
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [
                Plan.stop("checkin", start: 900, minutes: 20, place: SampleGuide.hotelId, kind: .logistics),
                Plan.stop("rest", start: 1000, minutes: 30, place: SampleGuide.hotelId, kind: .rest),
                stop("dinner", at: 1100, SampleGuide.hotelId)
            ]),
            SampleGuide.day(on: "2026-11-23", stops: [
                Plan.stop("checkin2", start: 900, minutes: 20, place: SampleGuide.hotelId, kind: .logistics),
                stop("breakfast", at: 480, SampleGuide.hotelId),
                stop("dinner2", at: 1100, SampleGuide.hotelId)
            ])
        ]
        #expect(repeats(Plan.issues(Plan.guide(days: days, places: [hotel]))).isEmpty)
    }

    @Test func restAtACafeIsNotCountedAsAUseOfIt() {
        let days = [
            SampleGuide.day(on: "2026-11-22", stops: [stop("rest", at: 600, kind: .rest)]),
            SampleGuide.day(on: "2026-11-23", stops: [stop("breakfast", at: 480)]),
            SampleGuide.day(on: "2026-11-24", stops: [stop("meal2", at: 480)])
        ]
        let found = repeats(Plan.issues(Plan.guide(days: days, places: [cafe()])))
        #expect(found.map(\.stopId) == ["meal2"])
        #expect(found.first?.message == "Test Cafe is already used on 2026-11-23 at 08:00. Use a different place here.")
    }

    @Test func theFinishedEdinburghSampleHasNoRepeatedPlaces() throws {
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
        #expect(repeats(Plan.issues(guide)).isEmpty)
    }

    @Test func theEdinburghMockFixtureHasNoRepeatedPlaces() throws {
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
        #expect(repeats(Plan.issues(guide)).isEmpty)
    }
}
