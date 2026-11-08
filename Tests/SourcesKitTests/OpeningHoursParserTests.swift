import GuideKit
import SourcesKit
import Testing

struct OpeningHoursParserTests {
    private func period(_ day: Weekday, _ open: String, _ close: String) -> WeeklyPeriod {
        WeeklyPeriod(weekday: day, open: Samples.time(open), close: Samples.time(close))
    }

    private func weekday(_ open: String, _ close: String) -> [WeeklyPeriod] {
        Weekday.allCases.map { period($0, open, close) }
    }

    private func days(_ names: [Weekday], _ open: String, _ close: String) -> [WeeklyPeriod] {
        names.map { period($0, open, close) }
    }

    // MARK: The strings the probe saw

    @Test func splitWeekdaysWithDifferentHours() {
        let reading = OpeningHoursParser.parse("Mo-Th 12:00-20:15; Fr-Sa 12:00-21:15; Su 12:00-19:45")
        #expect(reading.hours.hoursKnown)
        #expect(reading.reason == nil)
        #expect(reading.warnings.isEmpty)
        let expected = days([.monday, .tuesday, .wednesday, .thursday], "12:00", "20:15")
            + days([.friday, .saturday], "12:00", "21:15")
            + days([.sunday], "12:00", "19:45")
        #expect(reading.hours.weekly == expected)
    }

    @Test func everydayUntilMidnightClosesNextDay() {
        let reading = OpeningHoursParser.parse("Mo-Su 12:00-00:00")
        #expect(reading.hours.hoursKnown)
        #expect(reading.hours.weekly == weekday("12:00", "00:00"))
        #expect(reading.hours.weekly.allSatisfy { $0.closesNextDay })
    }

    @Test func sundayOnly() {
        let reading = OpeningHoursParser.parse("Su 10:00-17:00")
        #expect(reading.hours.hoursKnown)
        #expect(reading.hours.weekly == [period(.sunday, "10:00", "17:00")])
    }

    @Test func everydayWithOneRange() {
        let reading = OpeningHoursParser.parse("Mo-Su 11:00-17:00")
        #expect(reading.hours.hoursKnown)
        #expect(reading.hours.weekly == weekday("11:00", "17:00"))
    }

    @Test func weekdaysAndSundayDiffer() {
        let reading = OpeningHoursParser.parse("Mo-Sa 07:00-22:00; Su 08:00-22:00")
        #expect(reading.hours.hoursKnown)
        let expected = days(Array(Weekday.allCases.prefix(6)), "07:00", "22:00")
            + days([.sunday], "08:00", "22:00")
        #expect(reading.hours.weekly == expected)
    }

    @Test func overnightOnWeekdaysAndShorterOnSunday() {
        let reading = OpeningHoursParser.parse("Mo-Sa 04:00-00:45; Su 06:00-00:45")
        #expect(reading.hours.hoursKnown)
        let expected = days(Array(Weekday.allCases.prefix(6)), "04:00", "00:45")
            + days([.sunday], "06:00", "00:45")
        #expect(reading.hours.weekly == expected)
        #expect(reading.hours.weekly.allSatisfy { $0.closesNextDay })
    }

    @Test func twentyFourSevenIsTwentyFourHours() {
        let reading = OpeningHoursParser.parse("24/7")
        #expect(reading.hours.hoursKnown)
        #expect(reading.hours.weekly.count == 7)
        #expect(reading.hours.weekly.allSatisfy { $0.isOpen24Hours })
    }

    @Test func dateRangesAreNotGuessed() {
        let text = "Jan 01-Mar 24: 07:00-18:00; Mar 25-Apr 21: 07:00-19:00; Dec 25 off"
        let reading = OpeningHoursParser.parse(text)
        #expect(!reading.hours.hoursKnown)
        #expect(reading.hours.weekly.isEmpty)
        #expect(reading.reason?.contains("month or date") == true)
    }

    // MARK: Day selectors

    @Test func listsAndRangesOfDays() {
        let reading = OpeningHoursParser.parse("Mo-Fr,Su 09:00-17:00")
        #expect(reading.hours.weekly == days(Array(Weekday.allCases.prefix(5)) + [.sunday], "09:00", "17:00"))
    }

    @Test func aRangeThatWrapsTheWeek() {
        let reading = OpeningHoursParser.parse("Fr-Mo 10:00-12:00")
        let expected = days([.monday, .friday, .saturday, .sunday], "10:00", "12:00")
        #expect(reading.hours.weekly == expected)
    }

    @Test func aSingleDayAsAList() {
        let reading = OpeningHoursParser.parse("Sa,Su 10:00-14:00")
        #expect(reading.hours.weekly == days([.saturday, .sunday], "10:00", "14:00"))
    }

    @Test func aTimeWithNoDaysMeansEveryDay() {
        let reading = OpeningHoursParser.parse("10:00-18:00")
        #expect(reading.hours.weekly == weekday("10:00", "18:00"))
    }

    // MARK: Time ranges

    @Test func severalTimeRangesInOneRule() {
        let reading = OpeningHoursParser.parse("Mo-Fr 09:00-12:00,13:00-17:00")
        let monday = [period(.monday, "09:00", "12:00"), period(.monday, "13:00", "17:00")]
        #expect(reading.hours.weekly.prefix(2).elementsEqual(monday))
        #expect(reading.hours.weekly.count == 10)
    }

    @Test func spacesAroundCommasAndDashesAreAllowed() {
        let reading = OpeningHoursParser.parse("Mo - Fr 08:00-12:00 , 13:00 - 17:00")
        #expect(reading.hours.hoursKnown)
        #expect(reading.hours.weekly.prefix(2).elementsEqual([
            period(.monday, "08:00", "12:00"),
            period(.monday, "13:00", "17:00")
        ]))
    }

    @Test func overnightRangeClosesNextDay() {
        let reading = OpeningHoursParser.parse("Mo-Fr 22:00-02:00")
        #expect(reading.hours.weekly.count == 5)
        #expect(reading.hours.weekly.allSatisfy { $0.closesNextDay })
    }

    @Test func aCloseAfterMidnightWrittenAsTwentyFourPlusIsBroughtBack() {
        let reading = OpeningHoursParser.parse("Mo 20:00-26:00")
        #expect(reading.hours.weekly == [period(.monday, "20:00", "02:00")])
    }

    @Test func aCloseOfTwentyFourHundredIsMidnight() {
        let reading = OpeningHoursParser.parse("Mo-Su 10:00-24:00")
        #expect(reading.hours.weekly == weekday("10:00", "00:00"))
    }

    @Test func aRangeFromMidnightToMidnightIsTwentyFourHours() {
        let reading = OpeningHoursParser.parse("Mo-Su 00:00-24:00")
        #expect(reading.hours.weekly.allSatisfy { $0.isOpen24Hours })
    }

    // MARK: Rule order and closures

    @Test func aLaterRuleReplacesTheEarlierOneForItsDays() {
        let reading = OpeningHoursParser.parse("Mo-Fr 08:00-12:00; Mo 10:00-11:00")
        let monday = [period(.monday, "10:00", "11:00")]
        let tuesday = [period(.tuesday, "08:00", "12:00")]
        #expect(reading.hours.weekly.first == monday.first)
        #expect(reading.hours.weekly.contains(tuesday[0]))
        #expect(reading.hours.weekly.count == 5)
    }

    @Test func aDayMarkedOffIsClosed() {
        let reading = OpeningHoursParser.parse("Mo-Su 10:00-16:00; We off")
        #expect(reading.hours.hoursKnown)
        #expect(!reading.hours.weekly.contains { $0.weekday == .wednesday })
        #expect(reading.hours.weekly.count == 6)
    }

    @Test func everyDayOffIsKnownAndClosed() {
        let reading = OpeningHoursParser.parse("Mo-Su off")
        #expect(reading.hours.hoursKnown)
        #expect(reading.hours.weekly.isEmpty)
    }

    @Test func aLaterOffOverridesTwentyFourSeven() {
        let reading = OpeningHoursParser.parse("24/7; Mo off")
        #expect(reading.hours.weekly.count == 6)
        #expect(!reading.hours.weekly.contains { $0.weekday == .monday })
    }

    @Test func closedIsTheSameAsOff() {
        let reading = OpeningHoursParser.parse("Mo-Su 10:00-16:00; Su closed")
        #expect(reading.hours.weekly.count == 6)
    }

    // MARK: Public and school holidays

    @Test func publicHolidayRulesAreLeftOutWithAWarning() {
        let reading = OpeningHoursParser.parse("Mo-Su 10:00-16:00; PH off")
        #expect(reading.hours.hoursKnown)
        #expect(reading.hours.weekly.count == 7)
        #expect(reading.warnings.count == 1)
        #expect(reading.warnings.first?.lowercased().contains("holiday") == true)
    }

    @Test func holidayPartOfAListIsLeftOutAndTheRestIsKept() {
        let reading = OpeningHoursParser.parse("Mo-Fr,PH 10:00-12:00")
        #expect(reading.hours.weekly == days(Array(Weekday.allCases.prefix(5)), "10:00", "12:00"))
        #expect(reading.warnings.count == 1)
    }

    @Test func schoolHolidayRulesAreLeftOutWithAWarning() {
        let reading = OpeningHoursParser.parse("Mo-Fr 10:00-16:00; SH off")
        #expect(reading.hours.weekly.count == 5)
        #expect(reading.warnings.count == 1)
    }

    @Test func onlyHolidayRulesGiveUnknownHours() {
        let reading = OpeningHoursParser.parse("PH off")
        #expect(!reading.hours.hoursKnown)
        #expect(reading.reason?.contains("public holiday") == true)
        #expect(reading.warnings.count == 1)
    }

    // MARK: Unsupported syntax, and bad input, are unknown with a reason

    @Test func weekNumbersAreUnknown() {
        let reading = OpeningHoursParser.parse("week 1-53/2 Mo 10:00-12:00")
        #expect(!reading.hours.hoursKnown)
        #expect(reading.reason?.contains("week") == true)
    }

    @Test func sunriseAndSunsetAreUnknown() {
        let reading = OpeningHoursParser.parse("Mo-Fr sunrise-sunset")
        #expect(!reading.hours.hoursKnown)
        #expect(reading.reason?.contains("sunrise") == true)
    }

    @Test func commentsAreUnknown() {
        let reading = OpeningHoursParser.parse("Mo-Fr 10:00-18:00 \"by appointment\"")
        #expect(!reading.hours.hoursKnown)
        #expect(reading.reason?.contains("comment") == true)
    }

    @Test func openEndedTimesAreUnknown() {
        let reading = OpeningHoursParser.parse("Mo-Fr 10:00+")
        #expect(!reading.hours.hoursKnown)
        #expect(reading.reason != nil)
    }

    @Test func aPartThatCannotBeReadMakesTheWholeStringUnknown() {
        let reading = OpeningHoursParser.parse("Mo-Fr 10:00-12:00; Sa 09:00-13:00 by arrangement")
        #expect(!reading.hours.hoursKnown)
        #expect(reading.hours.weekly.isEmpty)
    }

    @Test func impossibleTimesAreUnknown() {
        #expect(!OpeningHoursParser.parse("Mo-Fr 25:00-26:00").hours.hoursKnown)
        #expect(!OpeningHoursParser.parse("Mo-Fr 10:61-12:00").hours.hoursKnown)
    }

    @Test func singleDigitHoursAreRefused() {
        #expect(!OpeningHoursParser.parse("Mo-Fr 9:00-17:00").hours.hoursKnown)
    }

    @Test func emptyTextIsUnknown() {
        let reading = OpeningHoursParser.parse("  ;  ")
        #expect(!reading.hours.hoursKnown)
        #expect(reading.reason == "no opening hours given")
    }

    @Test func aRuleWithOnlyADayIsUnknown() {
        #expect(!OpeningHoursParser.parse("Mo").hours.hoursKnown)
    }

    @Test func unknownDayCodesAreUnknown() {
        #expect(!OpeningHoursParser.parse("Xx 10:00-12:00").hours.hoursKnown)
        #expect(!OpeningHoursParser.parse("Mo-Fr/2 10:00-12:00").hours.hoursKnown)
    }
}
