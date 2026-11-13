/// Where the travellers sleep, with check-in and check-out times, and how their bags are handled.
///
/// Only a stay the traveller named has a place: `placeId`, `checkIn` and `checkOut` are nil otherwise, and the guide
/// never invents one. Guides made before `arrangement` was recorded always have a place; see
/// `Guide.stayArrangement` for how they are read.
public struct Stay: Hashable, Sendable, Codable {
    /// The place where the travellers sleep. Nil unless `arrangement` is `booked`.
    public let placeId: String?
    /// Check-in time on the first day. Nil when there is no stay, or no night in the trip.
    public let checkIn: LocalTime?
    /// Check-out time on the last day. Nil when there is no stay, or no night in the trip.
    public let checkOut: LocalTime?
    public let luggage: LuggageSlot?
    /// True when the travellers carry only hand luggage, so no bag drops or bag talk. Nil means not said.
    public let handLuggageOnly: Bool?
    /// Whether the travellers have a stay the guide knows about. Nil in guides made before it was recorded.
    public let arrangement: StayArrangement?
    /// True when `checkIn` and `checkOut` are typical times, not times from the traveller or a booking.
    /// Nil means the times were given.
    public let timesEstimated: Bool?

    public init(placeId: String?, checkIn: LocalTime?, checkOut: LocalTime?, luggage: LuggageSlot?,
                handLuggageOnly: Bool? = nil, arrangement: StayArrangement? = nil, timesEstimated: Bool? = nil) {
        self.placeId = placeId
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.luggage = luggage
        self.handLuggageOnly = handLuggageOnly
        self.arrangement = arrangement
        self.timesEstimated = timesEstimated
    }

    /// True when `placeId` names this stay's place. Always false for a nil id or a stay with no place, so a stop with
    /// no place is never mistaken for a stop at the stay.
    public func holds(_ placeId: String?) -> Bool {
        guard let placeId, let own = self.placeId else { return false }
        return placeId == own
    }
}
