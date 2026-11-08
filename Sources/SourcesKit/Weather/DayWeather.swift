import GuideKit

/// The weather for one day. `rainChance` is 0 to 100, or nil when the source gives none. `isForecast` is false for a
/// typical day taken from last year's archive.
public struct DayWeather: Sendable, Equatable {
    public let date: LocalDate
    public let rainChance: Int?
    public let tempMax: Double?
    public let tempMin: Double?
    public let summary: String
    public let isForecast: Bool

    public init(
        date: LocalDate,
        rainChance: Int?,
        tempMax: Double?,
        tempMin: Double?,
        summary: String,
        isForecast: Bool
    ) {
        self.date = date
        self.rainChance = rainChance
        self.tempMax = tempMax
        self.tempMin = tempMin
        self.summary = summary
        self.isForecast = isForecast
    }
}

/// The days of weather for a place, and the time zone the source used for them.
public struct WeatherOutlook: Sendable, Equatable {
    /// An IANA identifier such as "Europe/London", as the source returned it.
    public let timeZoneId: String
    public let days: [DayWeather]
}

/// Short words for the WMO weather codes that Open-Meteo returns.
public enum WeatherSummary {
    private static let words: [Int: String] = [
        0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
        45: "Fog", 48: "Fog",
        51: "Drizzle", 53: "Drizzle", 55: "Drizzle",
        56: "Freezing drizzle", 57: "Freezing drizzle",
        61: "Rain", 63: "Rain", 65: "Rain",
        66: "Freezing rain", 67: "Freezing rain",
        71: "Snow", 73: "Snow", 75: "Snow", 77: "Snow grains",
        80: "Rain showers", 81: "Rain showers", 82: "Rain showers",
        85: "Snow showers", 86: "Snow showers",
        95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with hail"
    ]

    /// The short words for a WMO code. "Weather unknown" for a missing or unlisted code.
    public static func text(for code: Int?) -> String {
        guard let code, let text = words[code] else { return "Weather unknown" }
        return text
    }
}
