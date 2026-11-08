import Foundation
import GuideKit
import SourcesKit
import Testing

struct OpenMeteoWeatherSourceTests {
    private let today = Samples.date("2026-11-08")
    private let centre = Samples.coordinate(55.9533, -3.1883)

    private let forecastJSON = """
    {"latitude":55.9533,"longitude":-3.1883,"timezone":"Europe/London","utc_offset_seconds":0,
     "daily_units":{"time":"iso8601","weather_code":"wmo code","temperature_2m_max":"°C"},
     "daily":{"time":["2026-11-08","2026-11-09","2026-11-10"],
              "weather_code":[61,3,0],
              "temperature_2m_max":[9.4,8.1,null],
              "temperature_2m_min":[4.2,3.0,2.5],
              "precipitation_probability_max":[80,10,null]}}
    """

    /// One day of archive values for a fixture year. Nil means the source had no value.
    struct ArchiveDay {
        let rain: Double?
        let high: Double?
        let low: Double?
    }

    /// Archive JSON with `daily.precipitation_sum`, `temperature_2m_max` and `temperature_2m_min`, one entry per day.
    private func archiveJSON(_ days: [ArchiveDay]) -> String {
        func list(_ values: [Double?]) -> String {
            values.map { value in value.map { String($0) } ?? "null" }.joined(separator: ",")
        }
        let times = Array(repeating: "\"2026-01-01\"", count: days.count).joined(separator: ",")
        return """
        {"timezone":"Europe/London",
         "daily":{"time":[\(times)],
                  "temperature_2m_max":[\(list(days.map(\.high)))],
                  "temperature_2m_min":[\(list(days.map(\.low)))],
                  "precipitation_sum":[\(list(days.map(\.rain)))]}}
        """
    }

    /// Answers each archive request with the fixture for the year in its `start_date`.
    private func archive(_ yearly: [Int: [ArchiveDay]]) -> @Sendable (URLRequest) -> HTTPResponse {
        let bodies = yearly.mapValues { archiveJSON($0) }
        return { request in
            let year = Samples.query(request)["start_date"].flatMap { Int($0.prefix(4)) } ?? 0
            guard let body = bodies[year] else { return Samples.response("{}", status: 404) }
            return Samples.response(body)
        }
    }

    private func outlook(
        start: String,
        end: String,
        respond: @escaping @Sendable (URLRequest) -> HTTPResponse,
        clock: FakeClock = FakeClock()
    ) async throws -> (WeatherOutlook, RecordingFetcher) {
        let fetcher = RecordingFetcher(answer: respond)
        let source = OpenMeteoWeatherSource(
            fetcher: fetcher,
            interval: .seconds(1),
            now: { clock.now },
            sleep: { clock.sleep($0) }
        )
        let result = try await source.outlook(
            at: centre,
            from: Samples.date(start),
            to: Samples.date(end),
            today: today
        )
        return (result, fetcher)
    }

    // MARK: Forecast

    @Test func aRangeInsideTheNextSixteenDaysUsesOneForecastRequestWithRainChances() async throws {
        let (result, fetcher) = try await outlook(
            start: "2026-11-08",
            end: "2026-11-10",
            respond: { _ in Samples.response(self.forecastJSON) }
        )
        #expect(result.timeZoneId == "Europe/London")
        #expect(result.days.count == 3)
        let first = result.days[0]
        #expect(first.date == Samples.date("2026-11-08"))
        #expect(first.rainChance == 80)
        #expect(first.summary == "Rain")
        #expect(first.tempMax == 9.4)
        #expect(first.tempMin == 4.2)
        #expect(first.isForecast)
        #expect(result.days[1].rainChance == 10)
        #expect(result.days[1].summary == "Overcast")
        #expect(result.days[2].rainChance == nil)
        #expect(result.days[2].tempMax == nil)
        let requests = await fetcher.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.host == "api.open-meteo.com")
        #expect(request.url?.path == "/v1/forecast")
        let query = Samples.query(request)
        #expect(query["timezone"] == "auto")
        #expect(query["start_date"] == "2026-11-08")
        #expect(query["end_date"] == "2026-11-10")
        #expect(query["daily"]?.contains("precipitation_probability_max") == true)
    }

    @Test func theLastForecastDayIsFifteenDaysAhead() async throws {
        let (result, fetcher) = try await outlook(
            start: "2026-11-23",
            end: "2026-11-23",
            respond: { _ in
                Samples.response("""
                {"timezone":"Europe/London","daily":{"time":["2026-11-23"],"weather_code":[0],
                 "temperature_2m_max":[7.0],"temperature_2m_min":[1.0],"precipitation_probability_max":[5]}}
                """)
            }
        )
        #expect(result.days.first?.isForecast == true)
        #expect(await fetcher.requests.count == 1)
    }

    // MARK: Typical days from the last three years

    @Test func typicalDaysAverageTheLastThreeYearsAndCountRainyDays() async throws {
        let responder = archive([
            2026: [ArchiveDay(rain: 2.0, high: 10, low: 2), ArchiveDay(rain: nil, high: 8, low: nil)],
            2025: [ArchiveDay(rain: 0.5, high: 12, low: 4), ArchiveDay(rain: 0.0, high: nil, low: 1.0)],
            2024: [ArchiveDay(rain: 1.0, high: 14, low: 6), ArchiveDay(rain: 3.0, high: 10, low: 5)]
        ])
        let (result, _) = try await outlook(start: "2027-03-01", end: "2027-03-02", respond: responder)
        #expect(result.timeZoneId == "Europe/London")
        #expect(result.days.map(\.date) == [Samples.date("2027-03-01"), Samples.date("2027-03-02")])
        // Day one: two of three years reached 1.0 mm, so 67%. The mean high is 12 and the mean low is 4.
        #expect(result.days[0].rainChance == 67)
        #expect(result.days[0].tempMax == 12)
        #expect(result.days[0].tempMin == 4)
        // Day two: one of the two years with a value was rainy, so 50%. The highs are 8 and 10, the lows 1 and 5.
        #expect(result.days[1].rainChance == 50)
        #expect(result.days[1].tempMax == 9)
        #expect(result.days[1].tempMin == 3)
        #expect(result.days.allSatisfy { !$0.isForecast })
        #expect(result.days.allSatisfy { $0.summary == "typical (last 3 years)" })
    }

    @Test func threeArchiveRequestsCoverTheSameDatesInEachYearAndAreSpacedOut() async throws {
        let responder = archive([
            2026: [ArchiveDay(rain: 0, high: 1, low: 1), ArchiveDay(rain: 0, high: 1, low: 1)],
            2025: [ArchiveDay(rain: 0, high: 1, low: 1), ArchiveDay(rain: 0, high: 1, low: 1)],
            2024: [ArchiveDay(rain: 0, high: 1, low: 1), ArchiveDay(rain: 0, high: 1, low: 1)]
        ])
        let clock = FakeClock()
        let (_, fetcher) = try await outlook(
            start: "2027-03-01",
            end: "2027-03-02",
            respond: responder,
            clock: clock
        )
        let requests = await fetcher.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.url?.host == "archive-api.open-meteo.com" })
        #expect(requests.allSatisfy { $0.url?.path == "/v1/archive" })
        #expect(requests.map { Samples.query($0)["start_date"] } == ["2026-03-01", "2025-03-01", "2024-03-01"])
        #expect(requests.map { Samples.query($0)["end_date"] } == ["2026-03-02", "2025-03-02", "2024-03-02"])
        let daily = Samples.query(requests[0])["daily"] ?? ""
        #expect(daily.contains("precipitation_sum"))
        #expect(!daily.contains("precipitation_probability_max"))
        // The first request goes at once. Each later one waits one second.
        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
    }

    @Test func aDayWithNoRainValuesHasNoRainChance() async throws {
        let responder = archive([
            2026: [ArchiveDay(rain: nil, high: 10, low: 2)],
            2025: [ArchiveDay(rain: nil, high: 12, low: 4)],
            2024: [ArchiveDay(rain: nil, high: 14, low: 6)]
        ])
        let (result, _) = try await outlook(start: "2027-03-01", end: "2027-03-01", respond: responder)
        #expect(result.days.first?.rainChance == nil)
        #expect(result.days.first?.tempMax == 12)
    }

    @Test func aRainfallOfOneMillimetreCountsAsRainyButNinetyNineHundredthsDoesNot() async throws {
        let responder = archive([
            2026: [ArchiveDay(rain: 0.99, high: 10, low: 2)],
            2025: [ArchiveDay(rain: 1.0, high: 12, low: 4)],
            2024: [ArchiveDay(rain: 0.5, high: 14, low: 6)]
        ])
        let (result, _) = try await outlook(start: "2027-03-01", end: "2027-03-01", respond: responder)
        #expect(result.days.first?.rainChance == 33)
    }

    @Test func aRangeBeyondTheHorizonIsTypicalForAllOfItsDays() async throws {
        let responder = archive([
            2025: Array(repeating: ArchiveDay(rain: 0, high: 5, low: 1), count: 23),
            2024: Array(repeating: ArchiveDay(rain: 0, high: 5, low: 1), count: 23),
            2023: Array(repeating: ArchiveDay(rain: 0, high: 5, low: 1), count: 23)
        ])
        let (result, fetcher) = try await outlook(start: "2026-11-08", end: "2026-11-30", respond: responder)
        #expect(result.days.count == 23)
        #expect(result.days.allSatisfy { !$0.isForecast })
        #expect(await fetcher.requests.count == 3)
    }

    @Test func aDayAfterTheHorizonIsTypical() async throws {
        let responder = archive([
            2025: [ArchiveDay(rain: 0, high: 5, low: 1)],
            2024: [ArchiveDay(rain: 0, high: 5, low: 1)],
            2023: [ArchiveDay(rain: 0, high: 5, low: 1)]
        ])
        let (result, fetcher) = try await outlook(start: "2026-11-24", end: "2026-11-24", respond: responder)
        #expect(result.days.first?.isForecast == false)
        #expect(await fetcher.requests.count == 3)
    }

    // MARK: Failures

    @Test func aYearWithTheWrongNumberOfDaysIsMalformed() async {
        let responder = archive([
            2026: [ArchiveDay(rain: 0, high: 5, low: 1), ArchiveDay(rain: 0, high: 5, low: 1)],
            2025: [ArchiveDay(rain: 0, high: 5, low: 1), ArchiveDay(rain: 0, high: 5, low: 1)],
            2024: [ArchiveDay(rain: 0, high: 5, low: 1), ArchiveDay(rain: 0, high: 5, low: 1)]
        ])
        await #expect(throws: SourcesError.self) {
            try await outlook(start: "2027-03-01", end: "2027-03-03", respond: responder)
        }
    }

    @Test func aRangeThatEndsBeforeItStartsIsRefused() async {
        let fetcher = RecordingFetcher { _ in Samples.response("{}") }
        let source = OpenMeteoWeatherSource(fetcher: fetcher)
        await #expect(throws: SourcesError.self) {
            try await source.outlook(
                at: centre,
                from: Samples.date("2026-11-10"),
                to: Samples.date("2026-11-08"),
                today: today
            )
        }
        #expect(await fetcher.requests.isEmpty)
    }

    @Test func aServerErrorStatusIsAnError() async {
        await #expect(throws: SourcesError.http(status: 500)) {
            try await outlook(
                start: "2026-11-08",
                end: "2026-11-08",
                respond: { _ in Samples.response("{}", status: 500) }
            )
        }
    }

    @Test func weatherCodesBecomeShortWords() {
        #expect(WeatherSummary.text(for: 0) == "Clear sky")
        #expect(WeatherSummary.text(for: 63) == "Rain")
        #expect(WeatherSummary.text(for: 96) == "Thunderstorm with hail")
        #expect(WeatherSummary.text(for: 999) == "Weather unknown")
        #expect(WeatherSummary.text(for: nil) == "Weather unknown")
    }
}
