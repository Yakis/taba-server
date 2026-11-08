/// One stretch of opening, in minutes from the start of a date. `end` can pass 1440 (after midnight), and `start`
/// can be negative when the place opened the day before and is still open at the start of this date.
struct OpenWindow: Hashable, Sendable {
    let start: Int
    let end: Int
}

extension OpenWindow {
    /// A period from `open` to `close`. A close at or before the open means it runs past midnight, and a close
    /// equal to the open means open 24 hours.
    init(open: LocalTime, close: LocalTime) {
        self.start = open.minutesSinceMidnight
        self.end = close > open ? close.minutesSinceMidnight : close.minutesSinceMidnight + 1440
    }
}

extension OpeningHours {
    /// True when a stop from `start` to `end` (minutes from the start of `date`) fits in opening on `date`.
    /// A stop that runs past midnight also fits when the opening runs through midnight into the next day.
    func covers(_ start: Int, _ end: Int, on date: LocalDate) -> Bool {
        let windows = openWindows(on: date)
        if windows.contains(where: { $0.start <= start && end <= $0.end }) {
            return true
        }
        guard end > 1440, let next = date.adding(days: 1) else {
            return false
        }
        let openThroughMidnight = windows.contains { $0.start <= start && $0.end >= 1440 }
        let openAfterMidnight = openWindows(on: next).contains { $0.start <= 0 && end - 1440 <= $0.end }
        return openThroughMidnight && openAfterMidnight
    }

    /// The windows open on `date`, including overnight windows that began the day before.
    func openWindows(on date: LocalDate) -> [OpenWindow] {
        if exceptions.contains(where: { $0.date == date && $0.closed }) {
            return []
        }
        var windows = ownWindows(on: date)
        if let previous = date.adding(days: -1) {
            // Only the part of yesterday's windows that runs past midnight reaches into this date.
            let overnight = ownWindows(on: previous).filter { $0.end > 1440 }
            windows += overnight.map { OpenWindow(start: $0.start - 1440, end: $0.end - 1440) }
        }
        return windows
    }

    private func ownWindows(on date: LocalDate) -> [OpenWindow] {
        if let exception = exceptions.first(where: { $0.date == date }) {
            return exception.periods.map { OpenWindow(open: $0.open, close: $0.close) }
        }
        return weekly
            .filter { $0.weekday == date.weekday }
            .map { OpenWindow(open: $0.open, close: $0.close) }
    }
}
