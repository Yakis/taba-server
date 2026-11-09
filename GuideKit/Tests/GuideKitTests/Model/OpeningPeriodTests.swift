import GuideKit
import Testing

struct OpeningPeriodTests {
    @Test func sameDayWeeklyPeriodStaysOnOneDay() {
        let period = WeeklyPeriod(weekday: .monday, open: SampleGuide.time("09:00"), close: SampleGuide.time("17:00"))
        #expect(!period.closesNextDay)
        #expect(!period.isOpen24Hours)
    }

    @Test func overnightWeeklyPeriodClosesTheNextDay() {
        // A pub open 11:00 to 01:00.
        let period = WeeklyPeriod(weekday: .friday, open: SampleGuide.time("11:00"), close: SampleGuide.time("01:00"))
        #expect(period.closesNextDay)
        #expect(!period.isOpen24Hours)
    }

    @Test func twentyFourHourWeeklyPeriodHasEqualOpenAndClose() {
        let period = WeeklyPeriod(weekday: .saturday, open: SampleGuide.time("00:00"), close: SampleGuide.time("00:00"))
        #expect(period.closesNextDay)
        #expect(period.isOpen24Hours)
    }

    @Test func overnightTimePeriodClosesTheNextDay() {
        let period = TimePeriod(open: SampleGuide.time("22:00"), close: SampleGuide.time("02:00"))
        #expect(period.closesNextDay)
        #expect(!period.isOpen24Hours)
    }

    @Test func twentyFourHourTimePeriodHasEqualOpenAndClose() {
        let period = TimePeriod(open: SampleGuide.time("10:00"), close: SampleGuide.time("10:00"))
        #expect(period.closesNextDay)
        #expect(period.isOpen24Hours)
    }
}
