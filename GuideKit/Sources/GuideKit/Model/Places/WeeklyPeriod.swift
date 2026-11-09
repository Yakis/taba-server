/// One regular opening period on a given weekday.
///
/// Times follow one rule. A `close` after `open` is a same-day period. A `close` at or before `open` means the
/// period runs past midnight and closes the next day (11:00 to 01:00). `close == open` means open 24 hours.
public struct WeeklyPeriod: Hashable, Sendable, Codable {
    public let weekday: Weekday
    public let open: LocalTime
    public let close: LocalTime

    public init(weekday: Weekday, open: LocalTime, close: LocalTime) {
        self.weekday = weekday
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
