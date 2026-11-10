import GuideKit
import Testing

/// The arrival and leaving times the traveller types, used when there is no transport booking.
struct TypedArrivalTests {
    private var cafe: Place { Plan.place("cafe", hours: Plan.alwaysOpen) }

    private func trip(arrives: String? = nil, leaves: String? = nil) -> Trip {
        let base = SampleGuide.trip()
        let dates = TripDates(start: base.dates.start, end: base.dates.end,
                              arrives: arrives.map(SampleGuide.time), leaves: leaves.map(SampleGuide.time))
        return Trip(destination: base.destination, dates: dates, party: base.party, budget: base.budget,
                    interests: base.interests, pace: base.pace, voice: base.voice)
    }

    private func meal(_ id: String, _ slot: MealSlot, at start: Int) -> Stop {
        Plan.stop(id, start: start, minutes: 45, place: "cafe", kind: .meal, meal: slot, flexible: true)
    }

    @Test func aStopBeforeTheTypedArrivalFires() throws {
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("early", start: 600, minutes: 30, place: "cafe")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], trip: trip(arrives: "14:00")))
        let early = try #require(issues.first { $0.kind == .beforeArrival })
        #expect(early.stopId == "early")
        #expect(early.message.contains("you arrive at 14:00"))
        #expect(!early.message.contains("train"))
    }

    @Test func breakfastAndLunchAreNotMissingBeforeALateArrival() {
        let day = SampleGuide.day(on: "2026-11-22", stops: [meal("d", .dinner, at: 1140)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], trip: trip(arrives: "16:00")))
        #expect(!issues.contains { $0.kind == .mealMissing && $0.date == SampleGuide.date("2026-11-22") })
        #expect(!Plan.has(issues, .beforeArrival))
    }

    @Test func withoutTypedTimesTheFirstDayNeedsEveryMeal() {
        let day = SampleGuide.day(on: "2026-11-22", stops: [meal("d", .dinner, at: 1140)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], trip: trip()))
        #expect(issues.contains { $0.kind == .mealMissing && $0.message.contains("breakfast") })
    }

    @Test func aStopTooCloseToTheTypedLeavingTimeFires() throws {
        // Leaving at 15:00 means being away from the last stop by 14:30. The stop runs 14:00 to 14:45.
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("late", start: 840, minutes: 45, place: "cafe")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], trip: trip(leaves: "15:00")))
        let late = try #require(issues.first { $0.kind == .missedDeparture })
        #expect(late.message.contains("to be away at 15:00"))
    }

    @Test func aBookingWinsOverTheTypedArrival() {
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T10:00")
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("mid", start: 690, minutes: 30, place: "cafe")])
        let guide = Plan.guide(days: [day], places: [cafe], bookings: [arrival], trip: trip(arrives: "14:00"))
        #expect(!Plan.has(Plan.issues(guide), .beforeArrival))
    }
}
