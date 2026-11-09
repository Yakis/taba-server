import GuideKit
import PipelineKit
import SourcesKit
import Testing

struct DayOutlookWeatherTests {
    private static let unknown = WeatherSummary.text(for: nil)

    private func day(
        _ date: String = "2026-11-22",
        summary: String = "Rain",
        rain: Int? = 40,
        max: Double? = 12.5,
        min: Double? = -0.4,
        forecast: Bool = true
    ) -> DayWeather {
        DayWeather(date: LocalDate(date)!, rainChance: rain, tempMax: max, tempMin: min, summary: summary,
                   isForecast: forecast)
    }

    @Test func temperaturesRoundToTheNearestWholeDegree() throws {
        let outlook = try #require(DayOutlook(day(max: 12.5, min: -0.4)))
        #expect(outlook.highCelsius == 13)
        #expect(outlook.lowCelsius == 0)
    }

    @Test func missingTemperaturesStayNil() throws {
        let outlook = try #require(DayOutlook(day(max: nil, min: nil)))
        #expect(outlook.highCelsius == nil)
        #expect(outlook.lowCelsius == nil)
    }

    @Test func summaryRainChanceAndForecastFlagAreCopied() throws {
        let typical = try #require(DayOutlook(day(summary: "Clear sky", rain: 5, forecast: false)))
        #expect(typical == DayOutlook(summary: "Clear sky", highCelsius: 13, lowCelsius: 0, rainChance: 5,
                                      isForecast: false))
    }

    @Test func missingRainChanceStaysNil() throws {
        let outlook = try #require(DayOutlook(day(rain: nil)))
        #expect(outlook.rainChance == nil)
    }

    @Test func emptyUnknownDayGivesNoOutlook() {
        #expect(DayOutlook(day(summary: Self.unknown, rain: nil, max: nil, min: nil)) == nil)
    }

    @Test func unknownSummaryWithATemperatureStillGivesAnOutlook() throws {
        let outlook = try #require(DayOutlook(day(summary: Self.unknown, rain: nil, max: 8, min: nil)))
        #expect(outlook.summary == "Weather unknown")
        #expect(outlook.highCelsius == 8)
    }

    @Test func outlooksAreKeyedByDate() throws {
        let outlooks = DayOutlook.outlooks([
            day("2026-11-22", summary: "Rain"),
            day("2026-11-23", summary: "Overcast", rain: 0, max: 9, min: 3)
        ])
        #expect(outlooks.count == 2)
        #expect(outlooks[try #require(LocalDate("2026-11-22"))]?.summary == "Rain")
        #expect(outlooks[try #require(LocalDate("2026-11-23"))]?.summary == "Overcast")
    }

    @Test func outlooksKeepTheFirstEntryForADate() throws {
        let outlooks = DayOutlook.outlooks([
            day("2026-11-22", summary: "Rain"),
            day("2026-11-22", summary: "Overcast")
        ])
        #expect(outlooks.count == 1)
        #expect(outlooks[try #require(LocalDate("2026-11-22"))]?.summary == "Rain")
    }

    @Test func outlooksLeaveOutEmptyDays() {
        let outlooks = DayOutlook.outlooks([day(summary: Self.unknown, rain: nil, max: nil, min: nil)])
        #expect(outlooks.isEmpty)
        #expect(DayOutlook.outlooks([]).isEmpty)
    }
}
