@testable import GuideKit
import Testing

/// The walk-or-ride rule, and how the checks use the ride's minutes.
struct TravelRuleTests {
    @Test func walkUpToTheLimitStaysAWalk() {
        let leg = Travel.leg(walkMinutes: 30, metres: 2_000)
        #expect(leg.mode == .walk)
        #expect(leg.minutes == 30)
        #expect(leg.metres == 2_000)
    }

    @Test func walkOverTheLimitBecomesARide() {
        let leg = Travel.leg(walkMinutes: 31, metres: 5_000)
        #expect(leg.mode == .transit)
        #expect(leg.minutes == Travel.rideMinutes(metres: 5_000))
        #expect(leg.metres == 5_000)
    }

    @Test func rideIsTenMinutesPlusRoadDistanceAtThirtyKilometresAnHour() {
        // 11 200 metres straight is 14 560 metres of road: 10 + ceil(14 560 / 500) = 10 + 30.
        #expect(Travel.rideMinutes(metres: 11_200) == 40)
        #expect(Travel.rideMinutes(metres: 0) == 10)
    }

    @Test func farPairBecomesATransitLegWithTheStraightLineMetres() {
        let origin = SampleGuide.coordinate(55.9533, -3.1883)
        let destination = SampleGuide.coordinate(55.9533 + 0.100719, -3.1883)
        let leg = Travel.leg(from: origin, to: destination, walkTimes: StraightLineWalkTimes())
        #expect(leg.mode == .transit)
        #expect(leg.minutes == 40)
        #expect(abs(leg.metres - 11_200) <= 1)
    }

    @Test func nearbyPairStaysAWalk() {
        let origin = SampleGuide.coordinate(55.9533, -3.1883)
        let destination = SampleGuide.coordinate(55.9533 + 0.008993, -3.1883)
        let leg = Travel.leg(from: origin, to: destination, walkTimes: StraightLineWalkTimes())
        #expect(leg.mode == .walk)
        #expect(leg.minutes == StraightLineWalkTimes().minutes(from: origin, to: destination))
        #expect(leg.minutes <= Travel.longestWalkMinutes)
    }
}

/// A far stop at 11 km, so the walk is over 30 minutes and the leg is a ride of 40 minutes.
struct RideTimingAndPaceTests {
    private var hall: Place { Plan.place("hall", name: "Test Hall", hours: Plan.alwaysOpen) }
    private var far: Place {
        Plan.place(
            "far",
            name: "Far Hall",
            hours: Plan.alwaysOpen,
            at: SampleGuide.coordinate(55.9533 + 0.100719, -3.1883)
        )
    }

    @Test func timingUsesTheRideMinutesForAFarPair() {
        // The ride takes 40 minutes, so a 20-minute gap is too tight and the message says bus or taxi.
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 600, minutes: 30, place: "hall"),
            Plan.stop("b", start: 650, minutes: 30, place: "far")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hall, far]))
        let tight = issues.first { $0.kind == .tightGap }
        #expect(tight?.severity == .error)
        #expect(tight?.message.contains("the bus or taxi takes about 40 minutes") == true)
    }

    @Test func timingAcceptsAGapLongEnoughForTheRide() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 600, minutes: 30, place: "hall"),
            Plan.stop("b", start: 675, minutes: 30, place: "far")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hall, far]))
        #expect(!Plan.has(issues, .tightGap))
        #expect(!Plan.has(issues, .shortGap))
    }

    @Test func paceIgnoresRideLegs() {
        // Three stops, each a ride apart: no walking, so no pace warning.
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 480, minutes: 30, place: "hall"),
            Plan.stop("b", start: 600, minutes: 30, place: "far"),
            Plan.stop("c", start: 720, minutes: 30, place: "hall")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hall, far]))
        #expect(!Plan.has(issues, .walkingOverPace))
    }

    @Test func stationJourneyUsesTheRideMinutes() {
        // The train arrives at 12:00 at a station 11 km out, so a stop at 12:20 is too early for a 40-minute ride.
        let station = Plan.place("station", name: "Far Station", kind: .station, hours: Plan.unknownHours,
                                 at: SampleGuide.coordinate(55.9533 + 0.100719, -3.1883))
        let booking = Booking(
            id: "train-in",
            kind: .train,
            from: "Elsewhere",
            fromPlaceId: nil,
            to: "Far Station",
            toPlaceId: "station",
            departs: SampleGuide.dateTime("2026-11-22T11:00"),
            arrives: SampleGuide.dateTime("2026-11-22T12:00"),
            notes: nil
        )
        let day = SampleGuide.day(on: "2026-11-22", stops: [Plan.stop("early", start: 740, minutes: 30, place: "hall")])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hall, station], bookings: [booking]))
        let early = issues.first { $0.kind == .beforeArrival }
        #expect(early?.stopId == "early")
        #expect(early?.message.contains("the journey from the station takes 40 minutes") == true)
    }
}

/// The assembler's legs: a walk between near places, and a ride to a place 11 km out.
struct AssemblerRideLegTests {
    private static func emptyCopy() -> GuideCopy {
        GuideCopy(
            hero: SampleGuide.hero(),
            days: [],
            stops: [],
            places: [],
            lists: [],
            tasting: [],
            notes: SampleGuide.notes()
        )
    }

    @Test func farStopGetsARideAndNearStopAWalk() {
        let hall = Plan.place("hall", hours: Plan.alwaysOpen)
        let near = Plan.place("near", hours: Plan.alwaysOpen, at: SampleGuide.coordinate(55.9533 + 0.008993, -3.1883))
        let far = Plan.place("far", hours: Plan.alwaysOpen, at: SampleGuide.coordinate(55.9533 + 0.100719, -3.1883))
        let facts = TripFacts(
            trip: SampleGuide.trip(),
            bookings: [],
            stay: SampleGuide.stay(),
            places: ["hall": hall, "near": near, "far": far],
            practical: [],
            sources: []
        )
        func stop(_ id: String, _ place: String, _ time: String) -> PlanDraftStop {
            PlanDraftStop(
                id: id,
                placeId: place,
                kind: .sight,
                mealSlot: nil,
                start: SampleGuide.time(time),
                minutes: 30,
                flexible: false,
                alternative: nil,
                reason: "Test",
                findingIds: []
            )
        }
        let draft = PlanDraft(
            days: [PlanDraftDay(date: SampleGuide.date("2026-11-22"), theme: "Day", stops: [
                stop("d1-s1", "hall", "09:00"),
                stop("d1-s2", "near", "10:00"),
                stop("d1-s3", "far", "12:00")
            ])],
            lists: [],
            skippedMeals: [],
            openQuestions: [],
            changes: []
        )
        let guide = GuideAssembler(walkTimes: StraightLineWalkTimes())
            .assemble(id: "rides", facts: facts, draft: draft, copy: Self.emptyCopy()).guide
        let stops = guide.days[0].stops
        #expect(stops[1].legFromPrevious?.mode == .walk)
        #expect(stops[2].legFromPrevious?.mode == .transit)
        let metres = Travel.metres(from: near.location.coordinate, to: far.location.coordinate)
        #expect(stops[2].legFromPrevious?.minutes == Travel.rideMinutes(metres: metres))
    }
}

struct RenderLegTextTests {
    @Test func walkTextKeepsTheWalkWording() {
        #expect(RenderLeg.text(Leg(mode: .walk, minutes: 8, metres: 600), previousPlaceId: "a", placeId: "b")
            == "8 min walk")
        #expect(RenderLeg.text(Leg(mode: .walk, minutes: 21, metres: 1_600), previousPlaceId: "a", placeId: "b")
            == "21 min walk · long walk")
    }

    @Test func rideTextSaysBusOrTaxi() {
        #expect(RenderLeg.text(Leg(mode: .transit, minutes: 40, metres: 11_200), previousPlaceId: "a", placeId: "b")
            == "40 min by bus or taxi")
    }

    @Test func shortOrSamePlaceLegsHaveNoRow() {
        #expect(RenderLeg.text(Leg(mode: .walk, minutes: 1, metres: 40), previousPlaceId: "a", placeId: "b") == nil)
        #expect(RenderLeg.text(Leg(mode: .walk, minutes: 5, metres: 400), previousPlaceId: "a", placeId: "a") == nil)
    }
}
