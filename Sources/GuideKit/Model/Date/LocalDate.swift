import Foundation

/// A calendar date with no time zone, written as "YYYY-MM-DD".
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil unless the year is 1...9999 and the date exists in the Gregorian calendar.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year) else { return nil }
        let calendar = UTCCalendar.make()
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        // Calendar rolls impossible values forward (2026-02-30 becomes 2026-03-02), so compare the round trip.
        let rolled = calendar.dateComponents([.year, .month, .day], from: date)
        guard rolled.year == year, rolled.month == month, rolled.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD". Returns nil for any other text, including impossible dates.
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = FixedWidthNumber.parse(parts[0], width: 4),
              let month = FixedWidthNumber.parse(parts[1], width: 2),
              let day = FixedWidthNumber.parse(parts[2], width: 2)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// The day of the week, computed with the Gregorian calendar in UTC.
    public var weekday: Weekday {
        let calendar = UTCCalendar.make()
        guard let date = calendarDate(in: calendar) else {
            preconditionFailure("A validated LocalDate always maps to a calendar date")
        }
        // Gregorian weekday components run from 1 (Sunday) to 7 (Saturday).
        let sundayFirst: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return sundayFirst[calendar.component(.weekday, from: date) - 1]
    }

    /// This date moved by `days` (negative goes backwards). Returns nil if the result leaves years 1...9999.
    public func adding(days: Int) -> LocalDate? {
        let calendar = UTCCalendar.make()
        guard let start = calendarDate(in: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: start)
        else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return LocalDate(year: year, month: month, day: day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        let yearText = FixedWidthNumber.format(year, width: 4)
        let monthText = FixedWidthNumber.format(month, width: 2)
        let dayText = FixedWidthNumber.format(day, width: 2)
        return "\(yearText)-\(monthText)-\(dayText)"
    }

    private func calendarDate(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid local date \"\(text)\", expected YYYY-MM-DD"
            )
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
