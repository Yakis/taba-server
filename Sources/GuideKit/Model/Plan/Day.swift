/// One day of the guide: its copy and its ordered stops.
public struct Day: Hashable, Sendable, Codable {
    public let date: LocalDate
    public let copy: DayCopy
    public let stops: [Stop]

    public init(date: LocalDate, copy: DayCopy, stops: [Stop]) {
        self.date = date
        self.copy = copy
        self.stops = stops
    }
}
