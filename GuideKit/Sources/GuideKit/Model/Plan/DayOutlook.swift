/// The expected weather for one day, as the guide shows it ("Rain likely, 8°").
public struct DayOutlook: Hashable, Sendable, Codable {
    /// A short phrase such as "Rain likely" or "Bright and cold".
    public let summary: String
    /// Highest and lowest temperature in whole degrees Celsius. Omitted when unknown.
    public let highCelsius: Int?
    public let lowCelsius: Int?
    /// Chance of rain from 0 to 100. Omitted when unknown.
    public let rainChance: Int?
    /// True for a real forecast, false for what is typical on that date (from past years).
    public let isForecast: Bool

    public init(
        summary: String,
        highCelsius: Int?,
        lowCelsius: Int?,
        rainChance: Int?,
        isForecast: Bool
    ) {
        self.summary = summary
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.rainChance = rainChance
        self.isForecast = isForecast
    }
}
