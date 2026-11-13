/// How the traveller gets to the city and back, as they said it.
public enum TravelMode: String, CaseIterable, Hashable, Sendable, Codable {
    case train
    case coach
    case flight
    case car
}

/// How the traveller reaches the city and leaves it, and where. The places are where the first day starts and the
/// last day ends: a station, an airport, a coach station or where they park. Ids are nil when the place is not known.
/// A transport booking on the same day takes precedence over these.
public struct TripTravel: Hashable, Sendable, Codable {
    public let mode: TravelMode
    /// Where the traveller arrives on the first day. Nil when not known.
    public let arrivalPlaceId: String?
    /// Where the traveller leaves from on the last day. Nil when not known.
    public let departurePlaceId: String?

    public init(mode: TravelMode, arrivalPlaceId: String?, departurePlaceId: String?) {
        self.mode = mode
        self.arrivalPlaceId = arrivalPlaceId
        self.departurePlaceId = departurePlaceId
    }
}
