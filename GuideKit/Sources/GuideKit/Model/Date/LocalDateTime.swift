/// A date and local time with no time zone, written as "YYYY-MM-DDTHH:MM".
/// The trip's time zone gives it its real-world meaning.
public struct LocalDateTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let date: LocalDate
    public let time: LocalTime

    public init(date: LocalDate, time: LocalTime) {
        self.date = date
        self.time = time
    }

    /// Parses "YYYY-MM-DDTHH:MM". Returns nil for any other text.
    public init?(_ string: String) {
        let parts = string.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let date = LocalDate(String(parts[0])),
              let time = LocalTime(String(parts[1]))
        else {
            return nil
        }
        self.date = date
        self.time = time
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        return lhs.time < rhs.time
    }

    public var description: String {
        "\(date.description)T\(time.description)"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = LocalDateTime(text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid local date-time \"\(text)\", expected YYYY-MM-DDTHH:MM"
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
