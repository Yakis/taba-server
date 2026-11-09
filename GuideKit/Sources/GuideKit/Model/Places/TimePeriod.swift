/// An open period on a specific date, with no weekday attached.
///
/// Times follow the same rule as `WeeklyPeriod`. `close` at or before `open` closes the next day,
/// and `close == open` means open 24 hours.
public struct TimePeriod: Hashable, Sendable, Codable {
    public let open: LocalTime
    public let close: LocalTime

    public init(open: LocalTime, close: LocalTime) {
        self.open = open
        self.close = close
    }

    /// True when the period runs past midnight. This includes the 24-hour case, where `close == open`.
    public var closesNextDay: Bool {
        close <= open
    }

    /// True when the period is open all day, with `close == open`.
    public var isOpen24Hours: Bool {
        close == open
    }
}
