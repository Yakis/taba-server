@testable import GuideKit
import Testing

struct RenderHoursTests {
    private static let sunday = SampleGuide.date("2025-11-23")
    private static let friday = SampleGuide.date("2025-11-21")
    private static let saturday = SampleGuide.date("2025-11-22")

    private static func weekly(_ weekday: Weekday, _ open: String, _ close: String) -> OpeningHours {
        OpeningHours(
            hoursKnown: true,
            weekly: [WeeklyPeriod(weekday: weekday, open: SampleGuide.time(open), close: SampleGuide.time(close))],
            exceptions: []
        )
    }

    private static func note(
        _ hours: OpeningHours,
        on date: LocalDate,
        at time: String,
        kind: PlaceKind = .cafe
    ) -> String? {
        RenderHours.atStop(hours, kind: kind, on: date, at: SampleGuide.time(time))?.text
    }

    @Test func weeklyHoursSayWhenThePlaceCloses() {
        let hours = Self.weekly(.sunday, "09:00", "17:00")
        #expect(Self.note(hours, on: Self.sunday, at: "12:00") == "Open until 17:00")
    }

    @Test func beforeOpeningTheNoteSaysWhenItOpens() {
        let hours = Self.weekly(.sunday, "09:00", "17:00")
        #expect(Self.note(hours, on: Self.sunday, at: "08:00") == "Opens 09:00")
    }

    @Test func afterClosingTheNoteSaysClosedByThen() {
        let hours = Self.weekly(.sunday, "09:00", "17:00")
        #expect(Self.note(hours, on: Self.sunday, at: "18:00") == "Closed by then")
    }

    @Test func aDayWithNoHoursIsClosedThatDay() {
        let hours = Self.weekly(.monday, "09:00", "17:00")
        #expect(Self.note(hours, on: Self.sunday, at: "12:00") == "Closed that day")
    }

    @Test func aClosedExceptionWinsOverTheWeeklyHours() {
        let base = Self.weekly(.sunday, "09:00", "17:00")
        let hours = OpeningHours(
            hoursKnown: true,
            weekly: base.weekly,
            exceptions: [DateException(date: Self.sunday, closed: true, periods: [])]
        )
        #expect(Self.note(hours, on: Self.sunday, at: "12:00") == "Closed that day")
    }

    @Test func exceptionPeriodsReplaceTheWeeklyPattern() {
        let periods = [
            TimePeriod(open: SampleGuide.time("10:00"), close: SampleGuide.time("13:00")),
            TimePeriod(open: SampleGuide.time("14:00"), close: SampleGuide.time("16:00"))
        ]
        let hours = OpeningHours(
            hoursKnown: true,
            weekly: Self.weekly(.sunday, "09:00", "17:00").weekly,
            exceptions: [DateException(date: Self.sunday, closed: false, periods: periods)]
        )
        #expect(Self.note(hours, on: Self.sunday, at: "12:00") == "Open until 13:00")
        #expect(Self.note(hours, on: Self.sunday, at: "13:30") == "Opens 14:00")
    }

    @Test func anOvernightPeriodStaysOpenIntoTheNextMorning() {
        let hours = Self.weekly(.friday, "11:00", "01:00")
        #expect(Self.note(hours, on: Self.friday, at: "23:00") == "Open until 01:00")
        #expect(Self.note(hours, on: Self.saturday, at: "00:30") == "Open until 01:00")
        #expect(Self.note(hours, on: Self.saturday, at: "02:00") == "Closed that day")
    }

    @Test func aPeriodOfEqualOpenAndCloseIsOpenAllDay() {
        let hours = Self.weekly(.sunday, "00:00", "00:00")
        #expect(Self.note(hours, on: Self.sunday, at: "03:00") == "Open 24 hours")
    }

    @Test func unknownHoursAreUncertain() {
        let hours = OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
        let note = RenderHours.atStop(hours, kind: .cafe, on: Self.sunday, at: SampleGuide.time("12:00"))
        #expect(note == HoursNote(text: "Hours not confirmed", isUncertain: true))
    }

    @Test func placesWithoutHoursShowNoNote() {
        let hours = Self.weekly(.sunday, "09:00", "17:00")
        #expect(Self.note(hours, on: Self.sunday, at: "12:00", kind: .lodging) == nil)
        #expect(Self.note(hours, on: Self.sunday, at: "12:00", kind: .viewpoint) == nil)
    }

    @Test func dayTextListsEachPeriodInOrder() {
        let afternoon = TimePeriod(open: SampleGuide.time("14:00"), close: SampleGuide.time("22:00"))
        let morning = TimePeriod(open: SampleGuide.time("10:00"), close: SampleGuide.time("12:00"))
        #expect(RenderHours.dayText([afternoon, morning]) == "10:00–12:00, 14:00–22:00")
        #expect(RenderHours.dayText([]) == "Closed")
        #expect(RenderHours.dayText([TimePeriod(open: SampleGuide.time("00:00"), close: SampleGuide.time("00:00"))])
            == "Open 24 hours")
    }
}
