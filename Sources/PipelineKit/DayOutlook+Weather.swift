import GuideKit
import SourcesKit

extension DayOutlook {
    /// The guide's outlook for one day of fetched weather, with the temperatures rounded to whole degrees. Nil when the
    /// source gave nothing for the day: no summary, no temperatures and no rain chance.
    public init?(_ day: DayWeather) {
        let carriesNothing = day.summary == WeatherSummary.text(for: nil)
            && day.tempMax == nil && day.tempMin == nil && day.rainChance == nil
        guard !carriesNothing else { return nil }
        self.init(
            summary: day.summary,
            highCelsius: day.tempMax.map { Int($0.rounded()) },
            lowCelsius: day.tempMin.map { Int($0.rounded()) },
            rainChance: day.rainChance,
            isForecast: day.isForecast
        )
    }

    /// The outlooks for the days that carry something, keyed by date. When two entries share a date, the first one
    /// is kept and the later one is ignored.
    public static func outlooks(_ days: [DayWeather]) -> [LocalDate: DayOutlook] {
        var seen: Set<LocalDate> = []
        var outlooks: [LocalDate: DayOutlook] = [:]
        for day in days where seen.insert(day.date).inserted {
            if let outlook = DayOutlook(day) {
                outlooks[day.date] = outlook
            }
        }
        return outlooks
    }
}
