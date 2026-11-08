import FoursquareKit
import GuideKit
import Testing

struct HoursMapperTests {
    @Test func mapsDayNumbersAndTimes() throws {
        let place = try Samples.decodePlace(Samples.detailsJSON)
        let result = HoursMapper.openingHours(from: place.hours)
        #expect(result.skippedEntries == 1)
        #expect(result.hours.hoursKnown)
        let monday = try #require(result.hours.weekly.first { $0.weekday == .monday })
        #expect(monday.open == LocalTime("11:00"))
        #expect(monday.close == LocalTime("01:00"))
        #expect(monday.closesNextDay)
    }

    @Test func twentyFourHundredBecomesMidnightAndStillClosesNextDay() throws {
        let place = try Samples.decodePlace(Samples.detailsJSON)
        let result = HoursMapper.openingHours(from: place.hours)
        let sunday = try #require(result.hours.weekly.first { $0.weekday == .sunday })
        #expect(sunday.close == LocalTime("00:00"))
        #expect(sunday.closesNextDay)
    }

    @Test func dayNumbersRunMondayToSunday() throws {
        let json = """
        {"fsq_place_id":"x","name":"X","categories":[],
         "hours":{"regular":[{"day":2,"open":"0900","close":"1700"},{"day":7,"open":"0900","close":"1700"}]}}
        """
        let place = try Samples.decodePlace(json)
        let weekdays = HoursMapper.openingHours(from: place.hours).hours.weekly.map(\.weekday)
        #expect(weekdays == [.tuesday, .sunday])
    }

    @Test func noHoursMeansUnknown() throws {
        let place = try Samples.decodePlace("{\"fsq_place_id\":\"x\",\"name\":\"X\",\"categories\":[]}")
        let result = HoursMapper.openingHours(from: place.hours)
        #expect(!result.hours.hoursKnown)
        #expect(result.hours.weekly.isEmpty)
        #expect(result.skippedEntries == 0)
    }

    @Test func emptyRegularListMeansUnknown() throws {
        let json = "{\"fsq_place_id\":\"x\",\"name\":\"X\",\"categories\":[],\"hours\":{\"regular\":[]}}"
        let place = try Samples.decodePlace(json)
        #expect(!HoursMapper.openingHours(from: place.hours).hours.hoursKnown)
    }

    @Test func malformedTimesAreSkipped() throws {
        let json = """
        {"fsq_place_id":"x","name":"X","categories":[],
         "hours":{"regular":[{"day":1,"open":"9am","close":"1700"},{"day":1,"open":"0900","close":"1700"}]}}
        """
        let place = try Samples.decodePlace(json)
        let result = HoursMapper.openingHours(from: place.hours)
        #expect(result.skippedEntries == 1)
        #expect(result.hours.weekly.count == 1)
    }
}
