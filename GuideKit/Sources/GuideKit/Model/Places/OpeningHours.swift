/// When a place is open. `hoursKnown` is false when the hours have not been found.
public struct OpeningHours: Hashable, Sendable, Codable {
    public let hoursKnown: Bool
    public let weekly: [WeeklyPeriod]
    public let exceptions: [DateException]

    public init(hoursKnown: Bool, weekly: [WeeklyPeriod], exceptions: [DateException]) {
        self.hoursKnown = hoursKnown
        self.weekly = weekly
        self.exceptions = exceptions
    }
}
