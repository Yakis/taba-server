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

struct DaylightCheckTests {
    private let viewpoint = Plan.place("view", name: "Test Viewpoint", kind: .viewpoint, indoor: false)

    private func sight(_ id: String, startingAt start: Int, place: String = "view") -> Stop {
        Plan.stop(id, start: start, minutes: 30, place: place)
    }

    @Test func outdoorSightStartingAfterSunsetFires() {
        let sunset = Plan.sunsetMinutes(on: "2026-11-23")
        let day = SampleGuide.day(on: "2026-11-23", stops: [sight("late", startingAt: sunset + 10)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [viewpoint]))
        #expect(issues.contains(where: { $0.kind == .afterSunset && $0.severity == .error && $0.stopId == "late" }))
    }

    @Test func outdoorSightStartingAtSunsetFires() {
        let sunset = Plan.sunsetMinutes(on: "2026-11-23")
        let day = SampleGuide.day(on: "2026-11-23", stops: [sight("at", startingAt: sunset)])
        #expect(Plan.has(Plan.issues(Plan.guide(days: [day], places: [viewpoint])), .afterSunset))
    }

    @Test func outdoorSightStartingWithinHalfAnHourOfSunsetWarns() {
        // Starts 20 minutes before sunset, which is less than 30 minutes before it.
        let sunset = Plan.sunsetMinutes(on: "2026-11-23")
        let day = SampleGuide.day(on: "2026-11-23", stops: [sight("close", startingAt: sunset - 20)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [viewpoint]))
        #expect(issues.contains(where: { $0.kind == .nearSunset && $0.severity == .warning }))
        #expect(!Plan.has(issues, .afterSunset))
    }

    @Test func outdoorSightWellBeforeSunsetDoesNotFire() {
        let sunset = Plan.sunsetMinutes(on: "2026-11-23")
        let day = SampleGuide.day(on: "2026-11-23", stops: [sight("early", startingAt: sunset - 60)])
        let issues = Plan.issues(Plan.guide(days: [day], places: [viewpoint]))
        #expect(!Plan.has(issues, .afterSunset))
        #expect(!Plan.has(issues, .nearSunset))
    }

    @Test func indoorSightIsNotDaylightChecked() {
        let museum = Plan.place("museum", name: "Test Museum", kind: .museum, indoor: true)
        let sunset = Plan.sunsetMinutes(on: "2026-11-23")
        let day = SampleGuide.day(on: "2026-11-23", stops: [sight("inside", startingAt: sunset + 60, place: "museum")])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [museum])), .afterSunset))
    }

    @Test func marketAndLightsAreExemptFromDaylight() {
        let sunset = Plan.sunsetMinutes(on: "2026-11-23")
        let market = Plan.place("market", name: "Test Market", kind: .market, indoor: false)
        let lights = Plan.place("lights", name: "Test Christmas Lights", kind: .landmark, indoor: false)
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            sight("market", startingAt: sunset + 60, place: "market"),
            sight("lights", startingAt: sunset + 60, place: "lights")
        ])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [market, lights])), .afterSunset))
    }

    @Test func polarNightGivesNoDaylightIssueButAnInfo() throws {
        // Tromsø has no sunset on 2025-12-21, so no daylight issue is raised; the checker says so once.
        let tromso = try #require(Coordinate(latitude: 69.6492, longitude: 18.9553))
        let trip = Plan.trip(start: "2025-12-21", end: "2025-12-22", centre: tromso, timeZoneId: "Europe/Oslo")
        let day = SampleGuide.day(on: "2025-12-21", stops: [
            Plan.stop("view", start: 900, minutes: 60, place: "view"),
            Plan.stop("walk", start: 1000, minutes: 60, place: "view")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [viewpoint], trip: trip))
        #expect(!Plan.has(issues, .afterSunset))
        #expect(!Plan.has(issues, .nearSunset))
        let info = issues.filter { $0.kind == .noDaylightData }
        #expect(info.count == 1)
        #expect(info.first?.severity == .info)
    }
}
