/// The first and last local dates of the trip, inclusive, with the times the traveller arrives and leaves when known.
public struct TripDates: Hashable, Sendable, Codable {
    public let start: LocalDate
    public let end: LocalDate
    /// The local time the traveller reaches the city on `start`. Omitted when unknown: the day is then open from the
    /// morning. A transport booking that arrives on `start` takes precedence.
    public let arrives: LocalTime?
    /// The local time the traveller leaves the city on `end`. Omitted when unknown: the day then runs into the
    /// evening. A transport booking that departs on `end` takes precedence.
    public let leaves: LocalTime?

    public init(start: LocalDate, end: LocalDate, arrives: LocalTime? = nil, leaves: LocalTime? = nil) {
        self.start = start
        self.end = end
        self.arrives = arrives
        self.leaves = leaves
    }
}
