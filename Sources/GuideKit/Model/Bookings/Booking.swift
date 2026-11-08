/// A fixed commitment such as a train or a stay. Times are local to the place where they happen.
public struct Booking: Hashable, Sendable, Codable {
    public let id: String
    public let kind: BookingKind
    public let from: String
    public let to: String
    public let departs: LocalDateTime
    public let arrives: LocalDateTime
    public let notes: String?

    public init(
        id: String,
        kind: BookingKind,
        from: String,
        to: String,
        departs: LocalDateTime,
        arrives: LocalDateTime,
        notes: String?
    ) {
        self.id = id
        self.kind = kind
        self.from = from
        self.to = to
        self.departs = departs
        self.arrives = arrives
        self.notes = notes
    }
}
