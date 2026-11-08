/// Hours that differ from the usual weekly pattern on one date: closed, or special periods.
public struct DateException: Hashable, Sendable, Codable {
    public let date: LocalDate
    public let closed: Bool
    /// Empty when `closed` is true.
    public let periods: [TimePeriod]

    public init(date: LocalDate, closed: Bool, periods: [TimePeriod]) {
        self.date = date
        self.closed = closed
        self.periods = periods
    }
}
