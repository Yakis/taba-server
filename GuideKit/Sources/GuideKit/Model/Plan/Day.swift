/// One day of the guide: its copy and its ordered stops.
public struct Day: Hashable, Sendable, Codable {
    public let date: LocalDate
    public let copy: DayCopy
    public let stops: [Stop]
    /// The expected weather. Omitted until the weather is known.
    public let weather: DayOutlook?

    public init(date: LocalDate, copy: DayCopy, stops: [Stop], weather: DayOutlook? = nil) {
        self.date = date
        self.copy = copy
        self.stops = stops
        self.weather = weather
    }
}
