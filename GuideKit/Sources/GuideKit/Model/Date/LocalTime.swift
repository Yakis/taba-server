/// A time of day with no date or time zone, written as "HH:MM" (00:00 to 23:59).
public struct LocalTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// Minutes since midnight, 0 to 1439.
    public let minutesSinceMidnight: Int

    /// Returns nil unless the value is 0...1439.
    public init?(minutesSinceMidnight: Int) {
        guard (0..<1440).contains(minutesSinceMidnight) else { return nil }
        self.minutesSinceMidnight = minutesSinceMidnight
    }

    /// Returns nil unless hour is 0...23 and minute is 0...59.
    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.init(minutesSinceMidnight: hour * 60 + minute)
    }

    /// Parses "HH:MM". Returns nil for anything else, including "24:00" and "9:30".
    public init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = FixedWidthNumber.parse(parts[0], width: 2),
              let minute = FixedWidthNumber.parse(parts[1], width: 2)
        else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minutesSinceMidnight / 60 }

    public var minute: Int { minutesSinceMidnight % 60 }

    /// This time moved by `minutes`. Returns nil if the result would fall before 00:00 or after 23:59.
    /// It never wraps past midnight.
    public func adding(minutes: Int) -> LocalTime? {
        let (sum, overflowed) = minutesSinceMidnight.addingReportingOverflow(minutes)
        guard !overflowed else { return nil }
        return LocalTime(minutesSinceMidnight: sum)
    }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public var description: String {
        "\(FixedWidthNumber.format(hour, width: 2)):\(FixedWidthNumber.format(minute, width: 2))"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let time = LocalTime(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid local time \"\(text)\", expected HH:MM"
            )
        }
        self = time
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
