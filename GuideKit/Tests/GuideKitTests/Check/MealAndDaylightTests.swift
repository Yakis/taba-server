import GuideKit
import Testing

struct MealCheckTests {
    private func meal(_ id: String, _ slot: MealSlot, at start: Int) -> Stop {
        Plan.stop(id, start: start, minutes: 45, place: "cafe", kind: .meal, meal: slot, flexible: true)
    }

    private var cafe: Place { Plan.place("cafe", hours: Plan.alwaysOpen) }

    @Test func missingDinnerOnAFullDayFires() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [meal("b", .breakfast, at: 480), meal("l", .lunch, at: 750)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe]))
        #expect(issues.contains(where: { $0.kind == .mealMissing && $0.message.contains("dinner") }))
        #expect(!issues.contains(where: { $0.kind == .mealMissing && $0.message.contains("lunch") }))
    }

    @Test func allThreeMealsOnAFullDayDoNotFire() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            meal("b", .breakfast, at: 480), meal("l", .lunch, at: 750), meal("d", .dinner, at: 1140)
        ])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [cafe])), .mealMissing))
    }

    @Test func mealOutsideItsSlotIsInfoAndStillCounts() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            meal("b", .breakfast, at: 480), meal("l", .lunch, at: 750), meal("d", .dinner, at: 1000)
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe]))
        #expect(issues.contains(where: { $0.kind == .mealOffSlot && $0.severity == .info && $0.stopId == "d" }))
        #expect(!Plan.has(issues, .mealMissing))
    }

    @Test func arrivalDayNeedsOnlyMealsAfterArrival() {
        // The train arrives at 12:30, so breakfast is not needed. Lunch and dinner are.
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T12:30")
        let day = SampleGuide.day(on: "2026-11-22", stops: [meal("l", .lunch, at: 780), meal("d", .dinner, at: 1140)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], bookings: [arrival]))
        #expect(!Plan.has(issues, .mealMissing))
    }

    @Test func arrivalDayWithoutDinnerFires() {
        let arrival = SampleGuide.trainBooking(departs: "2026-11-22T08:00", arrives: "2026-11-22T12:30")
        let day = SampleGuide.day(on: "2026-11-22", stops: [meal("l", .lunch, at: 780)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe], bookings: [arrival]))
        #expect(issues.contains(where: { $0.kind == .mealMissing && $0.message.contains("dinner") }))
    }
}

/// Daylight no longer limits a plan: an outdoor stop may be timed for lit streets, markets or night views.
struct DaylightCheckTests {
    private let viewpoint = Plan.place("view", name: "Test Viewpoint", kind: .viewpoint, indoor: false)

    @Test(arguments: [-40, -10, 0, 12, 90])
    func outdoorSightsAreNeverFlaggedForDaylight(minutesFromSunset: Int) {
        let sunset = Plan.sunsetMinutes(on: "2026-11-23")
        let stop = Plan.stop("view-stop", start: sunset + minutesFromSunset, minutes: 30, place: "view")
        let day = SampleGuide.day(on: "2026-11-23", stops: [stop])
        let issues = Plan.issues(Plan.guide(days: [day], places: [viewpoint]))
        #expect(!Plan.has(issues, .afterSunset))
        #expect(!Plan.has(issues, .nearSunset))
        #expect(!Plan.has(issues, .noDaylightData))
    }
}
