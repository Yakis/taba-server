/// Opening hours as the HTML guide words them. The rules match the app's `HoursText` and `PlaceHoursRow`: a date
/// exception wins over the weekly pattern, a period that closes after midnight carries over to the next day, and
/// "close equals open" means open all day.
enum RenderHours {
    /// Kinds of place with no hours to show: outdoor public places, and stations, stays and luggage stores, which
    /// the timeline handles with its own times.
    static let withoutHours: Set<PlaceKind> = [.street, .neighbourhood, .viewpoint, .station, .lodging, .luggage]

    /// The note for a stop that starts at `time` on `date`, or nil when the place's hours are not shown.
    static func atStop(_ hours: OpeningHours, kind: PlaceKind, on date: LocalDate, at time: LocalTime) -> HoursNote? {
        guard !withoutHours.contains(kind) else { return nil }
        guard hours.hoursKnown else {
            return HoursNote(text: "Hours not confirmed", isUncertain: true)
        }
        if let close = carriedClose(hours, on: date, at: time) {
            return .known("Open until \(RenderText.time(close))")
        }
        return .known(stopText(periods(on: date, in: hours), at: time))
    }

    /// The periods on `date`. A date exception wins over the weekly pattern. Empty when the place is closed.
    static func periods(on date: LocalDate, in hours: OpeningHours) -> [TimePeriod] {
        if let exception = hours.exceptions.first(where: { $0.date == date }) {
            return exception.closed ? [] : exception.periods
        }
        return hours.weekly
            .filter { $0.weekday == date.weekday }
            .map { TimePeriod(open: $0.open, close: $0.close) }
    }

    /// "10:00–16:00", "12:00–15:00, 17:00–22:00", "Open 24 hours" or "Closed", for one day's periods.
    static func dayText(_ periods: [TimePeriod]) -> String {
        let sorted = periods.sorted { $0.open < $1.open }
        if sorted.isEmpty {
            return "Closed"
        }
        if sorted.contains(where: \.isOpen24Hours) {
            return "Open 24 hours"
        }
        return sorted
            .map { "\(RenderText.time($0.open))–\(RenderText.time($0.close))" }
            .joined(separator: ", ")
    }

    /// The words for a stop, given the day's periods.
    private static func stopText(_ today: [TimePeriod], at time: LocalTime) -> String {
        if today.contains(where: \.isOpen24Hours) {
            return "Open 24 hours"
        }
        if today.isEmpty {
            return "Closed that day"
        }
        if let period = today.first(where: { covers(time, $0) }) {
            return "Open until \(RenderText.time(period.close))"
        }
        let upcoming = today.filter { $0.open > time }
        if let next = upcoming.min(by: { $0.open < $1.open }) {
            return "Opens \(RenderText.time(next.open))"
        }
        return "Closed by then"
    }

    /// The close time of a period from the evening before that is still open at `time`, if there is one.
    private static func carriedClose(_ hours: OpeningHours, on date: LocalDate, at time: LocalTime) -> LocalTime? {
        guard let previous = date.adding(days: -1) else { return nil }
        let carried = periods(on: previous, in: hours).filter { $0.closesNextDay && !$0.isOpen24Hours }
        return carried.first(where: { time < $0.close })?.close
    }

    /// True when `time` is inside `period`. The close time itself is outside. A period that runs past midnight is
    /// open from its opening until the end of the day.
    private static func covers(_ time: LocalTime, _ period: TimePeriod) -> Bool {
        if period.closesNextDay {
            return time >= period.open
        }
        return period.open <= time && time < period.close
    }
}
