import GuideKit
import Testing

struct HoursCheckTests {
    private func weekly(_ weekday: Weekday, _ open: String, _ close: String) -> WeeklyPeriod {
        WeeklyPeriod(weekday: weekday, open: SampleGuide.time(open), close: SampleGuide.time(close))
    }

    private var sundayMarket: Place {
        Plan.place(
            "market",
            name: "Test Market",
            kind: .market,
            indoor: false,
            hours: Plan.hours([weekly(.sunday, "10:00", "16:00")])
        )
    }

    @Test func closedDayFires() {
        let monday = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("s1", start: 600, minutes: 60, place: "market")
        ])
        let issues = Plan.issues(Plan.guide(days: [monday], places: [sundayMarket]))
        #expect(Plan.has(issues, .closed))
    }

    @Test func openDayDoesNotFireClosedOrOutsideHours() {
        let sunday = SampleGuide.day(on: "2026-11-22", stops: [
            Plan.stop("s1", start: 600, minutes: 60, place: "market")
        ])
        let issues = Plan.issues(Plan.guide(days: [sunday], places: [sundayMarket]))
        #expect(!Plan.has(issues, .closed))
        #expect(!Plan.has(issues, .outsideHours))
    }

    @Test func stopOutsideOpeningFires() {
        let cafe = Plan.place("cafe", hours: Plan.hours(daily: "10:00", "16:00"))
        let day = SampleGuide.day(on: "2026-11-22", stops: [
            Plan.stop("s1", start: 930, minutes: 60, place: "cafe", kind: .meal, meal: .lunch)
        ])
        #expect(Plan.has(Plan.issues(Plan.guide(days: [day], places: [cafe])), .outsideHours))
    }

    @Test func stopInsideOpeningDoesNotFire() {
        let cafe = Plan.place("cafe", hours: Plan.hours(daily: "10:00", "16:00"))
        let day = SampleGuide.day(on: "2026-11-22", stops: [
            Plan.stop("s1", start: 600, minutes: 60, place: "cafe", kind: .meal, meal: .lunch)
        ])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [cafe])), .outsideHours))
    }

    @Test func dateExceptionClosesPlace() {
        let exception = DateException(date: SampleGuide.date("2026-11-23"), closed: true, periods: [])
        let nineToFive = Weekday.allCases.map { weekly($0, "09:00", "17:00") }
        let shop = Plan.place("shop", kind: .shop, hours: Plan.hours(nineToFive, exceptions: [exception]))
        let monday = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("s1", start: 600, minutes: 60, place: "shop")
        ])
        let tuesday = SampleGuide.day(on: "2026-11-24", stops: [
            Plan.stop("s2", start: 600, minutes: 60, place: "shop")
        ])
        let issues = Plan.issues(Plan.guide(days: [monday, tuesday], places: [shop]))
        #expect(issues.contains(where: { $0.kind == .closed && $0.stopId == "s1" }))
        #expect(!issues.contains(where: { $0.stopId == "s2" && $0.kind == .closed }))
    }

    @Test func overnightBarCoversLateStop() {
        // Open 17:00 to 01:00 every night. The 23:30 to 00:30 stop fits in Monday's window.
        let bar = Plan.place("bar", kind: .bar, hours: Plan.hours(daily: "17:00", "01:00"))
        let monday = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("late", start: 1410, minutes: 60, place: "bar", kind: .drink)
        ])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [monday], places: [bar])), .outsideHours))
    }

    @Test func overnightWindowCoversEarlyHoursOfNextDay() {
        let bar = Plan.place("bar", kind: .bar, hours: Plan.hours(daily: "17:00", "01:00"))
        let tuesday = SampleGuide.day(on: "2026-11-24", stops: [
            Plan.stop("inside", start: 15, minutes: 30, place: "bar", kind: .drink),
            Plan.stop("past", start: 45, minutes: 30, place: "bar", kind: .drink, flexible: true)
        ])
        let issues = Plan.issues(Plan.guide(days: [tuesday], places: [bar]))
        #expect(!issues.contains(where: { $0.stopId == "inside" && $0.kind == .outsideHours }))
        #expect(issues.contains(where: { $0.stopId == "past" && $0.kind == .outsideHours }))
    }

    @Test func twentyFourHourPlaceNeverFiresHours() {
        // Open all day and night. A stop from 23:00 to 01:00 runs past midnight, into the next day's opening.
        let hall = Plan.place("hall", hours: Plan.alwaysOpen)
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("night", start: 1380, minutes: 120, place: "hall")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [hall]))
        #expect(!Plan.has(issues, .outsideHours))
        #expect(!Plan.has(issues, .closed))
    }

    @Test func unknownHoursFixedStopWarns() {
        let cafe = Plan.place("cafe", hours: Plan.unknownHours)
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("fixed", start: 600, minutes: 60, place: "cafe", kind: .meal, meal: .lunch, flexible: false)
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe]))
        #expect(issues.contains(where: { $0.kind == .hoursUnknown && $0.severity == .warning }))
    }

    @Test func unknownHoursFlexibleStopOnlyInforms() {
        let cafe = Plan.place("cafe", hours: Plan.unknownHours)
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("flex", start: 600, minutes: 60, place: "cafe", kind: .meal, meal: .lunch, flexible: true)
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe]))
        #expect(issues.contains(where: { $0.kind == .hoursUnknown && $0.severity == .info }))
        #expect(!issues.contains(where: { $0.kind == .hoursUnknown && $0.severity == .warning }))
    }

    @Test func unknownHoursOutdoorPublicSpaceIsSkipped() {
        let street = Plan.place("street", name: "Test Street", kind: .street, indoor: false, hours: Plan.unknownHours)
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("walk", start: 600, minutes: 60, place: "street", kind: .sight, flexible: false)
        ])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [street])), .hoursUnknown))
    }
}

struct TimingCheckTests {
    private var cafe: Place { Plan.place("cafe", hours: Plan.alwaysOpen) }
    private var shop: Place { Plan.place("shop", kind: .shop, hours: Plan.alwaysOpen) }

    @Test func overlapFires() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 780, minutes: 60, place: "cafe"),
            Plan.stop("b", start: 810, minutes: 30, place: "cafe")
        ])
        #expect(Plan.has(Plan.issues(Plan.guide(days: [day], places: [cafe])), .overlap))
    }

    @Test func separatedStopsDoNotOverlap() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 780, minutes: 30, place: "cafe"),
            Plan.stop("b", start: 840, minutes: 30, place: "cafe")
        ])
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [day], places: [cafe])), .overlap))
    }

    @Test func gapShorterThanWalkFires() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 600, minutes: 30, place: "cafe"),
            Plan.stop("b", start: 640, minutes: 30, place: "shop")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe, shop]), walk: FixedWalk(fixedMinutes: 20))
        #expect(issues.contains(where: { $0.kind == .tightGap && $0.severity == .error }))
    }

    @Test func gapLongEnoughForWalkDoesNotFire() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 600, minutes: 30, place: "cafe"),
            Plan.stop("b", start: 655, minutes: 30, place: "shop")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe, shop]), walk: FixedWalk(fixedMinutes: 20))
        #expect(!Plan.has(issues, .tightGap))
        #expect(!Plan.has(issues, .shortGap))
    }

    @Test func shortGapBetweenAreasWarns() {
        // A 6-minute walk means different areas, so at least 10 minutes should be left. A gap of 7 warns.
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 600, minutes: 30, place: "cafe"),
            Plan.stop("b", start: 637, minutes: 30, place: "shop")
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe, shop]), walk: FixedWalk(fixedMinutes: 6))
        #expect(issues.contains(where: { $0.kind == .shortGap && $0.severity == .warning }))
    }

    @Test func shortGapInSameAreaWarnsUnderFiveMinutes() {
        let tight = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 600, minutes: 30, place: "cafe"),
            Plan.stop("b", start: 633, minutes: 30, place: "shop")
        ])
        let roomy = SampleGuide.day(on: "2026-11-24", stops: [
            Plan.stop("c", start: 600, minutes: 30, place: "cafe"),
            Plan.stop("d", start: 636, minutes: 30, place: "shop")
        ])
        let walk = FixedWalk(fixedMinutes: 1)
        #expect(Plan.has(Plan.issues(Plan.guide(days: [tight], places: [cafe, shop]), walk: walk), .shortGap))
        #expect(!Plan.has(Plan.issues(Plan.guide(days: [roomy], places: [cafe, shop]), walk: walk), .shortGap))
    }

    @Test func stopsWithoutPlacesSkipWalkChecks() {
        let day = SampleGuide.day(on: "2026-11-23", stops: [
            Plan.stop("a", start: 600, minutes: 30, place: "cafe"),
            Plan.stop("b", start: 631, minutes: 30, place: nil, kind: .rest)
        ])
        let issues = Plan.issues(Plan.guide(days: [day], places: [cafe]), walk: FixedWalk(fixedMinutes: 20))
        #expect(!Plan.has(issues, .tightGap))
        #expect(!Plan.has(issues, .shortGap))
    }
}
