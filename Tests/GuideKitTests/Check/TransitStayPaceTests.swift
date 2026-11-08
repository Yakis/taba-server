import GuideKit
import Testing

struct TransitCheckTests {
    private var cafe: Place { Plan.place("cafe", hours: Plan.alwaysOpen) }

    @Test func stopBeforeArrivalFires() {
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T12:00")
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("early", start: 690, minutes: 30, place: "cafe")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], bookings: [arrival]))
        #expect(issues.contains(where: { $0.kind == .beforeArrival && $0.stopId == "early" }))
    }

    @Test func stopAfterArrivalDoesNotFire() {
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T12:00")
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("later", start: 750, minutes: 30, place: "cafe")])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [cafe], bookings: [arrival])), .beforeArrival))
    }

    @Test func lastStopEndingTooLateForTrainFires() {
        // Train at 14:30 needs leaving by 14:00 (30 minutes early, no walk). The stop runs 13:00 to 14:20.
        let departure = SampleGuide.trainBooking(departs: "2026-11-24T14:30", arrives: "2026-11-24T16:30")
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("late", start: 780, minutes: 80, place: "cafe")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], bookings: [departure]))
        #expect(issues.contains(where: { $0.kind == .missedDeparture && $0.severity == .error && $0.stopId == "late" }))
    }

    @Test func lastStopWithTimeToSpareDoesNotFire() {
        let departure = SampleGuide.trainBooking(departs: "2026-11-24T14:30", arrives: "2026-11-24T16:30")
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("early", start: 720, minutes: 30, place: "cafe")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], bookings: [departure]))
        #expect(!Plan.has(issues, .missedDeparture))
        #expect(!Plan.has(issues, .tightDeparture))
    }

    @Test func lastStopCloseToLeaveByTimeWarns() {
        // Leave by 14:00. The stop runs 13:20 to 13:50, which is 10 minutes early.
        let departure = SampleGuide.trainBooking(departs: "2026-11-24T14:30", arrives: "2026-11-24T16:30")
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("tight", start: 800, minutes: 30, place: "cafe")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], bookings: [departure]))
        #expect(issues.contains(where: { $0.kind == .tightDeparture && $0.severity == .warning }))
        #expect(!Plan.has(issues, .missedDeparture))
    }
}

struct StayCheckTests {
    private var hotel: Place {
        Plan.place(SampleGuide.hotelId, name: "Test Hotel", kind: .lodging, hours: Plan.unknownHours)
    }
    private var cafe: Place { Plan.place("cafe", hours: Plan.alwaysOpen) }

    private func logistics(_ id: String, start: Int, place: String, minutes: Int = 20) -> Stop {
        Plan.stop(id, start: start, minutes: minutes, place: place, kind: .logistics)
    }

    @Test func checkInBeforeTimeFires() {
        // Check-in is 15:00, so a logistics stop at the stay at 14:00 is too early.
        let day = SampleGuide.day(on: "2026-11-22", stops: [logistics("early", start: 840, place: SampleGuide.hotelId)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hotel, cafe]))
        #expect(issues.contains(where: { $0.kind == .checkInEarly && $0.stopId == "early" }))
    }

    @Test func checkInAtTimeDoesNotFire() {
        let day = SampleGuide.day(on: "2026-11-22", stops: [logistics("ok", start: 900, place: SampleGuide.hotelId)])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [hotel, cafe])), .checkInEarly))
    }

    @Test func leavingAfterCheckOutWithoutBagsFires() {
        // Check-out is 10:00. The first stop away from the stay starts at 11:30 with no logistics at the stay.
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("away", start: 690, minutes: 60, place: "cafe")])
        #expect(Plan.has(Plan.issues(Plan.guide(days: [day], places: [hotel, cafe])), .checkOutLate))
    }

    @Test func checkOutWithLogisticsAtStayDoesNotFire() {
        let day = SampleGuide.day(on: "2026-11-24", stops: [
            logistics("checkout", start: 540, place: SampleGuide.hotelId),
            Plan.stop("away", start: 690, minutes: 60, place: "cafe")
        ])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [hotel, cafe])), .checkOutLate))
    }

    @Test func luggageStopOutsideHoursFires() {
        let store = Plan.place("store", name: "Test Store", kind: .luggage, hours: Plan.hours(daily: "09:00", "17:00"))
        let stay = SampleGuide.stay(placeId: SampleGuide.hotelId, luggagePlaceId: "store")
        let day = SampleGuide.day(on: "2026-11-24", stops: [logistics("late", start: 1080, place: "store")])
        #expect(Plan.has(Plan.issues(Plan.guide(days: [day], places: [hotel, store], stay: stay)), .luggageClosed))
    }

    @Test func luggageStopInsideHoursDoesNotFire() {
        let store = Plan.place("store", name: "Test Store", kind: .luggage, hours: Plan.hours(daily: "09:00", "17:00"))
        let stay = SampleGuide.stay(placeId: SampleGuide.hotelId, luggagePlaceId: "store")
        let day = SampleGuide.day(on: "2026-11-24", stops: [logistics("ok", start: 600, place: "store")])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [hotel, store], stay: stay)), .luggageClosed))
    }

    @Test func arrivingBeforeCheckInWithOpenStoreWarnsWhenBagsAreNotDropped() {
        let store = Plan.place("store", name: "Test Store", kind: .luggage, hours: Plan.hours(daily: "09:00", "17:00"))
        let stay = SampleGuide.stay(placeId: SampleGuide.hotelId, luggagePlaceId: "store")
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T10:00")
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("walk", start: 660, minutes: 30, place: "cafe")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hotel, store, cafe], bookings: [arrival], stay: stay))
        #expect(issues.contains(where: { $0.kind == .luggageUnused && $0.severity == .warning }))
    }

    @Test func droppingBagsOnArrivalDoesNotWarn() {
        let store = Plan.place("store", name: "Test Store", kind: .luggage, hours: Plan.hours(daily: "09:00", "17:00"))
        let stay = SampleGuide.stay(placeId: SampleGuide.hotelId, luggagePlaceId: "store")
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T10:00")
        let day = SampleGuide.day(on: "2026-11-22", stops: [logistics("bags", start: 660, place: "store")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hotel, store, cafe], bookings: [arrival], stay: stay))
        #expect(!Plan.has(issues, .luggageUnused))
    }

    @Test func departingWithOpenStoreWarnsWhenBagsAreNotDropped() {
        let store = Plan.place("store", name: "Test Store", kind: .luggage, hours: Plan.hours(daily: "09:00", "17:00"))
        let stay = SampleGuide.stay(placeId: SampleGuide.hotelId, luggagePlaceId: "store")
        let departure = SampleGuide.trainBooking(departs: "2026-11-24T14:30", arrives: "2026-11-24T16:30")
        let day = SampleGuide.day(on: "2026-11-24", stops: [Plan.stop("lunch", start: 720, minutes: 30, place: "cafe")])
        let guide = Plan.guide(days: [day], places: [hotel, store, cafe], bookings: [departure], stay: stay)
        let issues = Plan.issues(guide)
        #expect(issues.contains(where: { $0.kind == .luggageUnused }))
    }
}

struct PaceCheckTests {
    private var hall: Place { Plan.place("hall", name: "Test Hall", hours: Plan.alwaysOpen) }

    /// Stops an hour apart, each at a different place, so each pair has a walk.
    private func stops(_ count: Int) -> [Stop] {
        (0..<count).map { index in
            Plan.stop("s\(index)", start: 480 + index * 60, minutes: 30, place: "hall")
        }
    }

    @Test func dayOverPaceLimitWarns() {
        // Unhurried walking is 130 minutes, and the warning starts above 156. Seven stops make six walks of 30.
        let day = SampleGuide.day(on: "2026-11-23", stops: stops(7))
        let issues = Plan.issues(Plan.guide(days: [day], places: [hall]), walk: FixedWalk(fixedMinutes: 30))
        #expect(issues.contains(where: { $0.kind == .walkingOverPace && $0.severity == .warning }))
    }

    @Test func dayWithinPaceLimitDoesNotWarn() {
        // Four stops make three walks of 30, which is 90 minutes.
        let day = SampleGuide.day(on: "2026-11-23", stops: stops(4))
        let issues = Plan.issues(Plan.guide(days: [day], places: [hall]), walk: FixedWalk(fixedMinutes: 30))
        #expect(!Plan.has(issues, .walkingOverPace))
    }
}
