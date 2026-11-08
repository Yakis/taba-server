/// A fixed commitment such as a train or a stay. Times are local to the place where they happen.
///
/// `fromPlaceId` and `toPlaceId` name the places the booking starts and ends at (a station, for trains). They are
/// nil when the place is outside the guide, such as a city the traveller comes from.
public struct Booking: Hashable, Sendable, Codable {
    public let id: String
    public let kind: BookingKind
    public let from: String
    public let fromPlaceId: String?
    public let to: String
    public let toPlaceId: String?
    public let departs: LocalDateTime
    public let arrives: LocalDateTime
    public let notes: String?

    public init(
        id: String,
        kind: BookingKind,
        from: String,
        fromPlaceId: String?,
        to: String,
        toPlaceId: String?,
        departs: LocalDateTime,
        arrives: LocalDateTime,
        notes: String?
    ) {
        self.id = id
        self.kind = kind
        self.from = from
        self.fromPlaceId = fromPlaceId
        self.to = to
        self.toPlaceId = toPlaceId
        self.departs = departs
        self.arrives = arrives
        self.notes = notes
    }
}
