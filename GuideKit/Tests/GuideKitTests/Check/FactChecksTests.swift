import GuideKit
import Testing

/// Pick lists hold only the kinds of place that fit them.
struct ListKindFactCheckTests {
    private func issues(listing place: Place) -> [PlanIssue] {
        let guide = StayScenarios.guide(
            trip: StayScenarios.trip(start: "2026-11-22", end: "2026-11-22"),
            stay: StayScenarios.noStay,
            places: [place],
            lists: [PlaceList(title: "Eat", caption: "Lunch.", placeIds: [place.id], key: .eat)]
        )
        return Plan.issues(guide)
    }

    @Test func aMuseumInTheEatListWarns() throws {
        let museum = StayScenarios.museum()
        let issue = try #require(issues(listing: museum).first { $0.kind == .listKindMismatch })
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Testford Museum"))
        #expect(issue.message.contains("eat list"))
    }

    @Test func aFoodMarketInTheEatListIsFine() {
        let market = StayScenarios.place(StayScenarios.marketId, name: "Testford Market Hall", kind: .market)
        #expect(!Plan.has(issues(listing: market), .listKindMismatch))
    }
}

/// The arrival and leaving times the traveller types start and end at the station they name.
struct TypedTravelTimesFactCheckTests {
    private let fixedWalk = FixedWalk(fixedMinutes: 20)

    /// A one-day trip by train, with the station as the place the traveller arrives at and leaves from.
    private func guide(stops: [Stop], arrives: String? = nil, leaves: String? = nil) -> Guide {
        let travel = TripTravel(mode: .train, arrivalPlaceId: StayScenarios.stationId,
                                departurePlaceId: StayScenarios.stationId)
        return StayScenarios.guide(
            trip: StayScenarios.trip(start: "2026-11-22", end: "2026-11-22", travel: travel,
                                     arrives: arrives, leaves: leaves),
            stay: StayScenarios.noStay,
            places: [StayScenarios.station(), StayScenarios.cafe()],
            days: [StayScenarios.day("2026-11-22", stops: stops)]
        )
    }

    @Test func aStopBeforeTheWalkFromTheTypedArrivalStationFires() throws {
        // Arrive at 10:00 and walk 20 minutes from the station, so a stop at 10:05 is too early.
        let early = StayScenarios.stop("early", at: "10:05", minutes: 30, place: StayScenarios.cafeId)
        let issues = Plan.issues(guide(stops: [early], arrives: "10:00"), walk: fixedWalk)
        let issue = try #require(issues.first { $0.kind == .beforeArrival })
        #expect(issue.stopId == "early")
        #expect(issue.severity == .error)
    }

    @Test func aStopAfterTheWalkFromTheTypedArrivalStationDoesNotFire() {
        // The walk ends at 10:20, so a stop at 10:40 is fine.
        let later = StayScenarios.stop("later", at: "10:40", minutes: 30, place: StayScenarios.cafeId)
        let issues = Plan.issues(guide(stops: [later], arrives: "10:00"), walk: fixedWalk)
        #expect(!Plan.has(issues, .beforeArrival))
    }

    @Test func aLastStopEndingTooLateForTheTypedLeavingTimeFires() throws {
        // Leaving at 18:00 from the station with a 20-minute walk means leaving the stop by 17:10. This one ends 17:30.
        let late = StayScenarios.stop("late", at: "16:30", minutes: 60, place: StayScenarios.cafeId)
        let issues = Plan.issues(guide(stops: [late], leaves: "18:00"), walk: fixedWalk)
        let issue = try #require(issues.first { $0.kind == .missedDeparture })
        #expect(issue.stopId == "late")
        #expect(issue.severity == .error)
    }

    @Test func aLastStopWithTimeToSpareForTheTypedLeavingTimeDoesNotFire() {
        // This one ends at 16:30, forty minutes before the leave-by time.
        let early = StayScenarios.stop("early", at: "15:30", minutes: 60, place: StayScenarios.cafeId)
        let issues = Plan.issues(guide(stops: [early], leaves: "18:00"), walk: fixedWalk)
        #expect(!Plan.has(issues, .missedDeparture))
        #expect(!Plan.has(issues, .tightDeparture))
    }
}

/// Bags on a day trip with no check-in time: the store is open, and nothing leaves bags there.
struct DayTripLuggageFactCheckTests {
    private let cafeStop = StayScenarios.stop("coffee", at: "11:00", minutes: 45, place: StayScenarios.cafeId)

    @Test func bagsNotDroppedOnADayTripWarnsWithoutABeforeTime() throws {
        // The traveller arrives at 10:00 and the store is open all day, so the warning runs to the end of the day.
        let guide = StayScenarios.dayTripWithLuggageStore(stops: [cafeStop])
        let issue = try #require(Plan.issues(guide).first { $0.kind == .luggageUnused })
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("You arrive at 10:00"))
        #expect(!issue.message.contains("before 23:59"))
        #expect(!issue.message.contains("23:59"))
    }

    @Test func droppingBagsAtTheStoreOnADayTripDoesNotWarn() {
        let drop = StayScenarios.stop("drop", at: "10:30", minutes: 20, place: StayScenarios.storeId, kind: .logistics)
        let guide = StayScenarios.dayTripWithLuggageStore(stops: [drop, cafeStop])
        #expect(!Plan.has(Plan.issues(guide), .luggageUnused))
    }
}

/// The prose contradictions the checker reports as errors, with the stop id when the words are in a stop.
struct StayContradictionFactCheckTests {
    @Test func leedsLikeDayTripHasThreeContradictionsReportedAsErrors() {
        let issues = Plan.issues(StayScenarios.leedsLikeDayTrip()).filter { $0.kind == .stayContradiction }
        #expect(issues.count == 3)
        #expect(issues.allSatisfy { $0.severity == .error })
    }

    @Test func aContradictionInAStopCarriesTheStopId() {
        let issues = Plan.issues(StayScenarios.leedsLikeDayTrip()).filter { $0.kind == .stayContradiction }
        #expect(issues.contains { $0.stopId == "rest" })
    }

    @Test func openQuestionContradictionsHaveNoStopId() {
        let issues = Plan.issues(StayScenarios.leedsLikeDayTrip()).filter { $0.kind == .stayContradiction }
        #expect(issues.filter { $0.stopId == nil }.count == 2)
    }

    @Test func leedsLikeDayTripNamesEachContradictionPath() {
        let paths = Set(StayScenarios.leedsLikeDayTrip().contradictions.map(\.path))
        #expect(paths == ["openQuestions[0]", "openQuestions[1]", "stops[rest].placeId"])
    }
}
