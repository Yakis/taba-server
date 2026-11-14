import Foundation
import GuideKit
import Testing

/// Preference checks: the ranked interests, the pace of each day, drink stops and the daily spend. The places are
/// made here with the interests and price levels each check reads. Nothing here is a real place.

private let firstDay = "2026-11-22"
private let secondDay = "2026-11-23"

private func trip(
    interests: [String] = ["food", "pubs"],
    pace: Pace = .unhurried,
    spend: DailySpend = .moderate,
    days: Int = 2,
    arrives: String? = nil
) -> Trip {
    Trip(
        destination: Destination(name: "Testville", countryCode: "GB", timeZoneId: "Europe/London",
                                 centre: Plan.centre),
        dates: TripDates(start: SampleGuide.date(firstDay), end: SampleGuide.date(days == 1 ? firstDay : secondDay),
                         arrives: arrives.map(SampleGuide.time), leaves: nil),
        party: Party(adults: 2, children: 0, mobilityNotes: []),
        budget: Budget(currencyCode: "GBP", stayMaxPerNight: 150, dailySpend: spend),
        interests: interests,
        pace: pace,
        voice: "Plain."
    )
}

private func place(
    _ id: String,
    kind: PlaceKind = .cafe,
    priceLevel: Int? = nil,
    interests: [String]? = nil
) -> Place {
    Place(
        id: id,
        name: "Test \(id)",
        kind: kind,
        location: PlaceLocation(coordinate: Plan.centre, address: nil, approximate: false),
        hours: Plan.alwaysOpen,
        priceLevel: priceLevel,
        booking: PlaceBooking(needed: false, url: nil),
        indoor: true,
        images: [],
        facts: [],
        copy: nil,
        interests: interests
    )
}

/// A stop of `minutes` starting at `start` minutes after midnight. Sights are the default kind.
private func stop(_ id: String, _ start: Int, _ minutes: Int, _ place: String, kind: StopKind = .sight) -> Stop {
    Plan.stop(id, start: start, minutes: minutes, place: place, kind: kind)
}

private func guide(_ days: [Day], places: [Place], trip: Trip) -> Guide {
    Plan.guide(days: days, places: places, stay: StayScenarios.noStay, trip: trip)
}

private func issues(_ guide: Guide, _ kind: IssueKind) -> [PlanIssue] {
    Plan.issues(guide).filter { $0.kind == kind }
}

private func day(_ date: String, _ stops: [Stop]) -> Day {
    SampleGuide.day(on: date, stops: stops)
}

/// `count` sights on `date`, an hour apart from 09:00, each at its own cafe (see `sightPlaces`).
private func sights(_ count: Int, on date: String) -> Day {
    day(date, (0..<count).map { stop("sight-\($0)", 540 + $0 * 60, 40, "cafe-\($0)") })
}

private func sightPlaces(_ count: Int) -> [Place] {
    (0..<count).map { place("cafe-\($0)") }
}

/// A second full day with a 45-minute rest and `count` sights from 10:00. Tests that look at the first day use it so
/// the second day adds no findings of the kinds under test.
private func restingSecondDay(sights count: Int) -> Day {
    var stops = (0..<count).map { stop("late-\($0)", 600 + $0 * 60, 40, "cafe-\($0)") }
    stops.append(stop("late-rest", 1020, 45, "cafe-0", kind: .rest))
    return day(secondDay, stops)
}

struct PreferenceInterestCheckTests {
    private var interestPlaces: [Place] {
        [place("cafe", interests: ["food"]), place("pub-a", kind: .pub, interests: ["pubs"]),
         place("pub-b", kind: .pub, interests: ["pubs"])]
    }

    @Test func topInterestWarnsWhenALowerInterestGetsMoreMinutes() {
        let stops = [stop("coffee", 600, 30, "cafe"), stop("pub-1", 700, 40, "pub-a"), stop("pub-2", 800, 40, "pub-b")]
        let found = issues(guide([day(firstDay, stops)], places: interestPlaces, trip: trip()), .topInterestOutweighed)
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.message.contains("\"pubs\" gets 80 minutes") == true)
        #expect(found.first?.message.contains("\"food\" gets 30") == true)
    }

    @Test func topInterestWithTheMostMinutesDoesNotWarn() {
        let stops = [stop("coffee", 600, 80, "cafe"), stop("pub-1", 700, 30, "pub-a")]
        let found = issues(guide([day(firstDay, stops)], places: interestPlaces, trip: trip()), .topInterestOutweighed)
        #expect(found.isEmpty)
    }

    @Test func topInterestServedOnlyByAMealDoesNotWarn() {
        // Food is served only by a meal, which is not a main stop, so the top interest has no main-stop minutes.
        let meal = stop("lunch", 720, 60, "cafe", kind: .meal)
        let stops = [meal, stop("pub-1", 700, 40, "pub-a"), stop("pub-2", 800, 40, "pub-b")]
        let found = issues(guide([day(firstDay, stops)], places: interestPlaces, trip: trip()), .topInterestOutweighed)
        #expect(found.isEmpty)
    }

    @Test func interestChecksAreSilentWhenNoInterestsAreRecorded() {
        let places = [place("cafe"), place("pub-a", kind: .pub), place("pub-b", kind: .pub)]
        let stops = [stop("coffee", 600, 30, "cafe"), stop("pub-1", 700, 40, "pub-a"), stop("pub-2", 800, 40, "pub-b")]
        let found = Plan.issues(guide([day(firstDay, stops)], places: places, trip: trip()))
        #expect(!found.contains { $0.kind == .topInterestOutweighed || $0.kind == .interestDominates })
    }

    @Test func oneInterestTakingEveryMinuteDominates() {
        let places = (1...4).map { place("cafe-\($0)", interests: ["food"]) }
        let stops = (1...4).map { stop("coffee-\($0)", 540 + $0 * 60, 40, "cafe-\($0)") }
        let mixed = trip(interests: ["food", "pubs", "music"])
        let found = issues(guide([day(firstDay, stops)], places: places, trip: mixed),
                           .interestDominates)
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.message.contains("\"food\" takes 100%") == true)
    }

    @Test func aShareOfExactlyHalfDoesNotDominate() {
        let places = [place("cafe-1", interests: ["food"]), place("cafe-2", interests: ["food"]),
                      place("pub-1", kind: .pub, interests: ["pubs"]),
                      place("venue-1", kind: .venue, interests: ["music"])]
        let stops = [stop("a", 540, 40, "cafe-1"), stop("b", 600, 40, "cafe-2"),
                     stop("c", 660, 40, "pub-1"), stop("d", 720, 40, "venue-1")]
        let mixed = trip(interests: ["food", "pubs", "music"])
        let found = issues(guide([day(firstDay, stops)], places: places, trip: mixed),
                           .interestDominates)
        #expect(found.isEmpty)
    }

    @Test func threeMainStopsNeverDominate() {
        let places = (1...3).map { place("cafe-\($0)", interests: ["food"]) }
        let stops = (1...3).map { stop("coffee-\($0)", 540 + $0 * 60, 40, "cafe-\($0)") }
        let mixed = trip(interests: ["food", "pubs", "music"])
        let found = issues(guide([day(firstDay, stops)], places: places, trip: mixed),
                           .interestDominates)
        #expect(found.isEmpty)
    }

    @Test func twoInterestsNeverDominate() {
        let places = (1...4).map { place("cafe-\($0)", interests: ["food"]) }
        let stops = (1...4).map { stop("coffee-\($0)", 540 + $0 * 60, 40, "cafe-\($0)") }
        #expect(issues(guide([day(firstDay, stops)], places: places, trip: trip()), .interestDominates).isEmpty)
    }

    @Test func threeDrinkStopsOnADayWarnAtAnyPace() {
        let places = (1...3).map { place("pub-\($0)", kind: .pub) }
        let stops = (1...3).map { stop("drink-\($0)", 600 + $0 * 60, 40, "pub-\($0)", kind: .drink) }
        let found = issues(guide([day(firstDay, stops)], places: places, trip: trip(pace: .packed)), .drinkHeavyDay)
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.date == SampleGuide.date(firstDay))
    }

    @Test func twoDrinkStopsOnADayDoNotWarn() {
        let places = (1...2).map { place("pub-\($0)", kind: .pub) }
        let stops = (1...2).map { stop("drink-\($0)", 600 + $0 * 60, 40, "pub-\($0)", kind: .drink) }
        #expect(issues(guide([day(firstDay, stops)], places: places, trip: trip()), .drinkHeavyDay).isEmpty)
    }

    @Test func oneDayTripHasNoFullDays() {
        // One main stop, an early start and no rest on a one-day trip: none of the full-day checks apply.
        let places = (1...3).map { place("pub-\($0)", kind: .pub) }
        let stops = [stop("early", 450, 40, "pub-1"), stop("drink-2", 600, 40, "pub-2", kind: .drink),
                     stop("drink-3", 700, 40, "pub-3", kind: .drink)]
        let found = Plan.issues(guide([day(firstDay, stops)], places: places, trip: trip(pace: .relaxed, days: 1)))
        let kinds = Set(found.map(\.kind))
        #expect(kinds.isDisjoint(with: [.startsBeforePace, .restMissing, .mainStopsUnderPace]))
    }

    @Test func theEdinburghFixtureGetsNoInterestFindings() throws {
        let edinburgh = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
        let found = Plan.issues(edinburgh)
        #expect(!found.contains { $0.kind == .topInterestOutweighed || $0.kind == .interestDominates })
        #expect(issues(edinburgh, .restMissing).map(\.date) == [SampleGuide.date("2025-11-24")])
    }
}

struct PreferencePaceCheckTests {
    @Test func relaxedDayWithFiveMainStopsWarnsWithItsRange() {
        let found = issues(guide([sights(5, on: firstDay)], places: sightPlaces(5), trip: trip(pace: .relaxed)),
                           .mainStopsOverPace)
        #expect(found.count == 1)
        #expect(found.first?.severity == .warning)
        #expect(found.first?.message.contains("5 main stops") == true)
        #expect(found.first?.message.contains("3 to 4") == true)
    }

    @Test func unhurriedDayAtTheTopOfItsRangeDoesNotWarn() {
        let found = issues(guide([sights(5, on: firstDay)], places: sightPlaces(5), trip: trip(pace: .unhurried)),
                           .mainStopsOverPace)
        #expect(found.isEmpty)
    }

    @Test func unhurriedDayWithSixMainStopsWarns() {
        let found = issues(guide([sights(6, on: firstDay)], places: sightPlaces(6), trip: trip(pace: .unhurried)),
                           .mainStopsOverPace)
        #expect(found.count == 1)
    }

    @Test func packedDayHasNoUpperBound() {
        let found = issues(guide([sights(12, on: firstDay)], places: sightPlaces(12), trip: trip(pace: .packed)),
                           .mainStopsOverPace)
        #expect(found.isEmpty)
    }

    @Test func partialArrivalDayIsCheckedAgainstTheUpperBoundToo() {
        let days = [sights(5, on: firstDay), day(secondDay, [])]
        let found = issues(guide(days, places: sightPlaces(5), trip: trip(pace: .relaxed, arrives: "07:00")),
                           .mainStopsOverPace)
        #expect(found.count == 1)
    }

    @Test func fewMainStopsOnAFullDayIsInfoOnly() {
        let days = [sights(2, on: firstDay), restingSecondDay(sights: 3)]
        let found = issues(guide(days, places: sightPlaces(3), trip: trip(pace: .relaxed)), .mainStopsUnderPace)
        #expect(found.count == 1)
        #expect(found.first?.severity == .info)
        #expect(found.first?.date == SampleGuide.date(firstDay))
    }

    @Test func fewMainStopsOnAPartialDayIsNotReported() {
        let days = [sights(1, on: firstDay), restingSecondDay(sights: 3)]
        let found = issues(guide(days, places: sightPlaces(3), trip: trip(pace: .relaxed, arrives: "07:00")),
                           .mainStopsUnderPace)
        #expect(found.isEmpty)
    }

    @Test func packedFullDayWithTooFewStopsIsInfoOnly() {
        // Packed plans six or more, so a full day with two is reported as information, never as a warning.
        let days = [sights(2, on: firstDay), restingSecondDay(sights: 6)]
        let found = issues(guide(days, places: sightPlaces(6), trip: trip(pace: .packed)), .mainStopsUnderPace)
        #expect(found.count == 1)
        #expect(found.first?.severity == .info)
    }

    @Test func firstMainStopBeforeTheUnhurriedLimitWarns() {
        let stops = [stop("early", 510, 40, "cafe-0"), stop("later", 600, 40, "cafe-1")]
        let days = [day(firstDay, stops), restingSecondDay(sights: 3)]
        let found = issues(guide(days, places: sightPlaces(3), trip: trip(pace: .unhurried)), .startsBeforePace)
        #expect(found.count == 1)
        #expect(found.first?.stopId == "early")
        #expect(found.first?.severity == .warning)
    }

    @Test func firstMainStopAtTheLimitDoesNotWarn() {
        let days = [day(firstDay, [stop("on-time", 540, 40, "cafe-0")]), restingSecondDay(sights: 3)]
        #expect(issues(guide(days, places: sightPlaces(3), trip: trip(pace: .unhurried)), .startsBeforePace).isEmpty)
    }

    @Test func relaxedDayMayNotStartBeforeHalfPastNine() {
        let days = [day(firstDay, [stop("nine", 540, 40, "cafe-0")]), restingSecondDay(sights: 3)]
        let found = issues(guide(days, places: sightPlaces(3), trip: trip(pace: .relaxed)), .startsBeforePace)
        #expect(found.count == 1)
    }

    @Test func packedDayHasNoStartLimit() {
        let days = [day(firstDay, [stop("early", 450, 40, "cafe-0")]), restingSecondDay(sights: 6)]
        #expect(issues(guide(days, places: sightPlaces(6), trip: trip(pace: .packed)), .startsBeforePace).isEmpty)
    }

    @Test func fullDayWithoutRestWarnsOnRelaxedAndUnhurried() {
        let days = [sights(4, on: firstDay), day(secondDay, [stop("late", 540, 40, "cafe-0")])]
        let found = issues(guide(days, places: sightPlaces(4), trip: trip(pace: .unhurried)), .restMissing)
        #expect(found.map(\.date) == [SampleGuide.date(firstDay), SampleGuide.date(secondDay)])
        #expect(found.allSatisfy { $0.severity == .warning })
    }

    @Test func restOfFortyFiveMinutesSatisfiesTheRule() {
        let rest = stop("rest", 900, 45, "cafe-0", kind: .rest)
        let days = [day(firstDay, sights(4, on: firstDay).stops + [rest]), restingSecondDay(sights: 4)]
        #expect(issues(guide(days, places: sightPlaces(4), trip: trip()), .restMissing).isEmpty)
    }

    @Test func restOfFortyMinutesIsNotEnough() {
        let rest = stop("rest", 900, 40, "cafe-0", kind: .rest)
        let days = [day(firstDay, sights(4, on: firstDay).stops + [rest]), restingSecondDay(sights: 4)]
        let found = issues(guide(days, places: sightPlaces(4), trip: trip()), .restMissing)
        #expect(found.map(\.date) == [SampleGuide.date(firstDay)])
    }

    @Test func packedDayNeedsNoRest() {
        let days = [sights(6, on: firstDay), day(secondDay, [])]
        #expect(issues(guide(days, places: sightPlaces(6), trip: trip(pace: .packed)), .restMissing).isEmpty)
    }

    @Test func partialArrivalDayNeedsNoRest() {
        let days = [sights(4, on: firstDay), restingSecondDay(sights: 4)]
        #expect(issues(guide(days, places: sightPlaces(4), trip: trip(arrives: "07:00")), .restMissing).isEmpty)
    }

    @Test func oneDayTripStillWarnsOnTooManyMainStops() {
        let oneDay = trip(pace: .relaxed, days: 1)
        let found = issues(guide([sights(5, on: firstDay)], places: sightPlaces(5), trip: oneDay),
                           .mainStopsOverPace)
        #expect(found.count == 1)
    }

    @Test func mealAboveTheLowSpendCeilingWarns() {
        let places = [place("pricey", priceLevel: 3)]
        let meal = stop("dinner", 1080, 60, "pricey", kind: .meal)
        let found = issues(guide([day(firstDay, [meal])], places: places, trip: trip(spend: .low)), .overSpend)
        #expect(found.count == 1)
        #expect(found.first?.stopId == "dinner")
        #expect(found.first?.severity == .warning)
        #expect(found.first?.message == "Test pricey has price level 3, above the ceiling of 2 for a low daily spend.")
    }

    @Test func drinkAboveTheModerateCeilingWarns() {
        let places = [place("pricey-bar", kind: .bar, priceLevel: 4)]
        let drink = stop("drink", 1080, 60, "pricey-bar", kind: .drink)
        let found = issues(guide([day(firstDay, [drink])], places: places, trip: trip(spend: .moderate)), .overSpend)
        #expect(found.count == 1)
    }

    @Test func placesAtTheCeilingDoNotWarn() {
        let places = [place("cheap", priceLevel: 2), place("fair", priceLevel: 3)]
        let stops = [stop("lunch", 720, 60, "cheap", kind: .meal), stop("dinner", 1080, 60, "fair", kind: .meal)]
        #expect(issues(guide([day(firstDay, stops)], places: places, trip: trip(spend: .low)), .overSpend).count == 1)
        #expect(issues(guide([day(firstDay, stops)], places: places, trip: trip(spend: .moderate)), .overSpend).isEmpty)
    }

    @Test func highSpendHasNoCeiling() {
        let places = [place("pricey", priceLevel: 4)]
        let meal = stop("dinner", 1080, 60, "pricey", kind: .meal)
        #expect(issues(guide([day(firstDay, [meal])], places: places, trip: trip(spend: .high)), .overSpend).isEmpty)
    }

    @Test func unknownPriceLevelNeverWarns() {
        let places = [place("unknown")]
        let meal = stop("dinner", 1080, 60, "unknown", kind: .meal)
        #expect(issues(guide([day(firstDay, [meal])], places: places, trip: trip(spend: .low)), .overSpend).isEmpty)
    }

    @Test func sightsAreNotSpendChecked() {
        let places = [place("museum", kind: .museum, priceLevel: 4)]
        let sight = stop("museum-visit", 600, 60, "museum")
        #expect(issues(guide([day(firstDay, [sight])], places: places, trip: trip(spend: .low)), .overSpend).isEmpty)
    }
}

struct PacePreferenceTableTests {
    @Test func mainStopRangesFollowThePlanningTable() {
        #expect(Pace.relaxed.mainStopRange == 3...4)
        #expect(Pace.unhurried.mainStopRange == 4...5)
        #expect(Pace.packed.mainStopRange.lowerBound == 6)
        #expect(Pace.packed.mainStopRange.upperBound == Int.max)
    }

    @Test func firstMainStopLimitsFollowThePlanningTable() {
        #expect(Pace.relaxed.firstMainStopNotBefore == LocalTime("09:30"))
        #expect(Pace.unhurried.firstMainStopNotBefore == LocalTime("09:00"))
        #expect(Pace.packed.firstMainStopNotBefore == nil)
    }
}
