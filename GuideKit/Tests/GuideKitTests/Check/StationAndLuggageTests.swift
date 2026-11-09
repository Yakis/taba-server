import GuideKit
import Testing

/// Bookings that name their stations by place id, and the luggage gap rule.
struct StationCheckTests {
    private var cafe: Place { Plan.place("cafe", hours: Plan.alwaysOpen) }
    private var station: Place {
        Plan.place("station", name: "Test Station", kind: .station, hours: Plan.unknownHours)
    }

    private func arrival(toPlaceId: String?) -> Booking {
        Booking(
            id: "train-in",
            kind: .train,
            from: "Elsewhere",
            fromPlaceId: nil,
            to: "Test Station",
            toPlaceId: toPlaceId,
            departs: SampleGuide.dateTime("2026-11-22T11:00"),
            arrives: SampleGuide.dateTime("2026-11-22T12:00"),
            notes: nil
        )
    }

    private func departure(fromPlaceId: String?) -> Booking {
        Booking(
            id: "train-out",
            kind: .train,
            from: "Test Station",
            fromPlaceId: fromPlaceId,
            to: "Elsewhere",
            toPlaceId: nil,
            departs: SampleGuide.dateTime("2026-11-24T14:30"),
            arrives: SampleGuide.dateTime("2026-11-24T16:30"),
            notes: nil
        )
    }

    @Test func arrivalWalkUsesTheStationPlaceId() {
        // With the station named, the walk of 30 minutes means a 12:10 start is too early.
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("early", start: 730, minutes: 30, place: "cafe")])
        let guide = Plan.guide(days: [day], places: [cafe, station], bookings: [arrival(toPlaceId: "station")])
        #expect(Plan.has(Plan.issues(guide, walk: FixedWalk(fixedMinutes: 30)), .beforeArrival))
    }

    @Test func arrivalWithoutStationIdWalksZeroAndReportsInfo() {
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("early", start: 730, minutes: 30, place: "cafe")])
        let guide = Plan.guide(days: [day], places: [cafe, station], bookings: [arrival(toPlaceId: nil)])
        let issues = Plan.issues(guide, walk: FixedWalk(fixedMinutes: 30))
        #expect(!Plan.has(issues, .beforeArrival))
        #expect(issues.contains(where: { $0.kind == .stationUnknown && $0.severity == .info }))
    }

    @Test func namedStationDoesNotReportStationUnknown() {
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("later", start: 780, minutes: 30, place: "cafe")])
        let guide = Plan.guide(days: [day], places: [cafe, station], bookings: [arrival(toPlaceId: "station")])
        #expect(!Plan.has(Plan.issues(guide), .stationUnknown))
    }

    @Test func departureWalkUsesTheStationPlaceId() {
        // Leave by 13:30 with a 30-minute margin and a 30-minute walk. A stop running 12:40 to 13:40 is too late.
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("late", start: 760, minutes: 60, place: "cafe")])
        let guide = Plan.guide(days: [day], places: [cafe, station], bookings: [departure(fromPlaceId: "station")])
        #expect(Plan.has(Plan.issues(guide, walk: FixedWalk(fixedMinutes: 30)), .missedDeparture))
    }

    @Test func departureWithoutStationIdReportsInfoAndWalksZero() {
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("late", start: 760, minutes: 60, place: "cafe")])
        let guide = Plan.guide(days: [day], places: [cafe, station], bookings: [departure(fromPlaceId: nil)])
        let issues = Plan.issues(guide, walk: FixedWalk(fixedMinutes: 30))
        #expect(!Plan.has(issues, .missedDeparture))
        #expect(issues.contains(where: { $0.kind == .stationUnknown && $0.severity == .info }))
    }
}

struct LuggageGapTests {
    private var hotel: Place { Plan.place(SampleGuide.hotelId, name: "Test Hotel", kind: .lodging) }
    private var store: Place {
        Plan.place("store", name: "Test Store", kind: .luggage, hours: Plan.hours(daily: "09:00", "17:00"))
    }
    private var stay: Stay { SampleGuide.stay(placeId: SampleGuide.hotelId, luggagePlaceId: "store") }

    private func breakfast(start: Int, minutes: Int) -> Stop {
        Plan.stop("breakfast", start: start, minutes: minutes, place: SampleGuide.hotelId, kind: .meal,
                  meal: .breakfast, flexible: true)
    }

    @Test func arrivalGapEndsWhenTheFirstStopAtTheStayStarts() {
        // Arrive 10:00. Breakfast at the stay starts 10:30, so the gap is 10:00 to 10:30. A drop at 12:00 is too late.
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T10:00")
        let day = SampleGuide.day(on: "2026-11-22", stops: [
            breakfast(start: 630, minutes: 30),
            Plan.stop("drop", start: 720, minutes: 20, place: "store", kind: .logistics)
        ])
        let guide = Plan.guide(days: [day], places: [hotel, store], bookings: [arrival], stay: stay)
        #expect(Plan.has(Plan.issues(guide), .luggageUnused))
    }

    @Test func arrivalDropInsideTheGapCounts() {
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T10:00")
        let day = SampleGuide.day(on: "2026-11-22", stops: [
            breakfast(start: 630, minutes: 30),
            Plan.stop("drop", start: 615, minutes: 20, place: "store", kind: .logistics)
        ])
        let guide = Plan.guide(days: [day], places: [hotel, store], bookings: [arrival], stay: stay)
        #expect(!Plan.has(Plan.issues(guide), .luggageUnused))
    }

    @Test func departureGapStartsWhenTheLastStopAtTheStayEnds() {
        // Breakfast at the stay ends 09:30, before check-out at 10:00, so the gap starts at 09:30.
        // A drop at 09:15 is before the gap, so it does not count.
        let departure = SampleGuide.trainBooking(departs: "2026-11-24T14:30", arrives: "2026-11-24T16:30")
        let day = SampleGuide.day(on: "2026-11-24", stops: [
            breakfast(start: 510, minutes: 60),
            Plan.stop("drop", start: 555, minutes: 20, place: "store", kind: .logistics)
        ])
        let guide = Plan.guide(days: [day], places: [hotel, store], bookings: [departure], stay: stay)
        #expect(Plan.has(Plan.issues(guide), .luggageUnused))
    }

    @Test func departureDropInsideTheGapCounts() {
        let departure = SampleGuide.trainBooking(departs: "2026-11-24T14:30", arrives: "2026-11-24T16:30")
        let day = SampleGuide.day(on: "2026-11-24", stops: [
            breakfast(start: 510, minutes: 60),
            Plan.stop("drop", start: 585, minutes: 20, place: "store", kind: .logistics)
        ])
        let guide = Plan.guide(days: [day], places: [hotel, store], bookings: [departure], stay: stay)
        #expect(!Plan.has(Plan.issues(guide), .luggageUnused))
    }
}

struct UnknownHoursExemptionTests {
    @Test func lodgingStationAndLuggageWithUnknownHoursAreNotFlagged() {
        let lodging = Plan.place("lodging", name: "Test Lodging", kind: .lodging, hours: Plan.unknownHours)
        let station = Plan.place("station", name: "Test Station", kind: .station, hours: Plan.unknownHours)
        let luggage = Plan.place("luggage", name: "Test Store", kind: .luggage, hours: Plan.unknownHours)
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 480, minutes: 30, place: "lodging", kind: .meal, meal: .breakfast, flexible: true),
            Plan.stop("b", start: 600, minutes: 30, place: "station", kind: .travel, flexible: false),
            Plan.stop("c", start: 700, minutes: 30, place: "luggage", kind: .sight, flexible: false)
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [lodging, station, luggage]))
        #expect(!Plan.has(issues, .hoursUnknown))
    }
}

struct BookingReferenceTests {
    @Test func unknownStationIdIsAStructureProblem() {
        let booking = Booking(
            id: "train-in",
            kind: .train,
            from: "Elsewhere",
            fromPlaceId: nil,
            to: "Test Station",
            toPlaceId: "manual:nowhere",
            departs: SampleGuide.dateTime("2026-11-22T11:00"),
            arrives: SampleGuide.dateTime("2026-11-22T12:00"),
            notes: nil
        )
        let guide = SampleGuide.make(bookings: [booking])
        #expect(guide.structureProblems == [
            .unknownPlaceReference(placeId: "manual:nowhere", from: "booking train-in to")
        ])
    }
}
