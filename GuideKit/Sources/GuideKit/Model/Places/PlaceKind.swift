/// The kind of a place.
public enum PlaceKind: String, CaseIterable, Hashable, Sendable, Codable {
    case market
    case foodHall
    case cafe
    case restaurant
    case pub
    case bar
    /// A music or performance venue: a concert hall, a jazz club or a live music room.
    case venue
    case viewpoint
    case street
    case neighbourhood
    case landmark
    case museum
    case shop
    case grocery
    case station
    case lodging
    case luggage
    case other
}
