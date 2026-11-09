/// The first and last local dates of the trip, inclusive.
public struct TripDates: Hashable, Sendable, Codable {
    public let start: LocalDate
    public let end: LocalDate

    public init(start: LocalDate, end: LocalDate) {
        self.start = start
        self.end = end
    }
}
