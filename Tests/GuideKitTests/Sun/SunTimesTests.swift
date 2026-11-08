import GuideKit
import Testing

/// Reference times come from the sunrise-sunset.org API, which reports UTC. They are converted here to local
/// time: GMT in winter, BST (UTC+1) from 30 March 2025 to 26 October 2025. Tolerance is 2 minutes.
struct SunTimesTests {
    private func compute(_ date: String, _ latitude: Double, _ longitude: Double, _ zone: String) throws -> SunTimes {
        let coordinate = try #require(Coordinate(latitude: latitude, longitude: longitude))
        return try #require(SunTimes.compute(date: SampleGuide.date(date), at: coordinate, timeZoneId: zone))
    }

    private func isWithin2Minutes(_ actual: LocalTime?, _ expected: String) -> Bool {
        guard let actual, let expected = LocalTime(expected) else { return false }
        return abs(actual.minutesSinceMidnight - expected.minutesSinceMidnight) <= 2
    }

    @Test func edinburghOnTheSundayTheTripStarts() throws {
        // Reference 2025-11-23 (GMT): sunrise 08:05, sunset 15:53, civil twilight ends 16:37.
        let sun = try compute("2025-11-23", 55.9533, -3.1884, "Europe/London")
        #expect(isWithin2Minutes(sun.sunrise, "08:05"))
        #expect(isWithin2Minutes(sun.sunset, "15:53"))
        #expect(isWithin2Minutes(sun.blueHourEnds, "16:37"))
    }

    @Test func edinburghInMidsummer() throws {
        // Reference 2025-06-21 (BST): sunrise 04:26, sunset 22:03, civil twilight ends 23:05.
        let sun = try compute("2025-06-21", 55.9533, -3.1884, "Europe/London")
        #expect(isWithin2Minutes(sun.sunrise, "04:26"))
        #expect(isWithin2Minutes(sun.sunset, "22:03"))
        #expect(isWithin2Minutes(sun.blueHourEnds, "23:05"))
    }

    @Test func edinburghOnTheDayBritishSummerTimeStarts() throws {
        // Reference 2025-03-30 (BST starts at 01:00 UT): sunrise 06:47, sunset 19:47, civil twilight ends 20:25.
        let sun = try compute("2025-03-30", 55.9533, -3.1884, "Europe/London")
        #expect(isWithin2Minutes(sun.sunrise, "06:47"))
        #expect(isWithin2Minutes(sun.sunset, "19:47"))
        #expect(isWithin2Minutes(sun.blueHourEnds, "20:25"))
    }

    @Test func londonInDecember() throws {
        // Reference 2025-12-21 (GMT): sunrise 08:04, sunset 15:54, civil twilight ends 16:34.
        let sun = try compute("2025-12-21", 51.5072, -0.1276, "Europe/London")
        #expect(isWithin2Minutes(sun.sunrise, "08:04"))
        #expect(isWithin2Minutes(sun.sunset, "15:54"))
        #expect(isWithin2Minutes(sun.blueHourEnds, "16:34"))
    }

    @Test func tromsoInPolarNightHasNoSunriseOrSunset() throws {
        // The sun does not rise at Tromsø on 2025-12-21, so sunrise and sunset are nil. Civil twilight still
        // happens around midday (reference 12:53 UT, 13:53 CET).
        let sun = try compute("2025-12-21", 69.6492, 18.9553, "Europe/Oslo")
        #expect(sun.sunrise == nil)
        #expect(sun.sunset == nil)
        #expect(isWithin2Minutes(sun.blueHourEnds, "13:53"))
    }

    @Test func unknownTimeZoneGivesNoTimes() throws {
        let coordinate = try #require(Coordinate(latitude: 55.9533, longitude: -3.1884))
        let date = SampleGuide.date("2025-11-23")
        #expect(SunTimes.compute(date: date, at: coordinate, timeZoneId: "Mars/Olympus") == nil)
    }
}
