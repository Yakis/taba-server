/// The type of a booking.
public enum BookingKind: String, CaseIterable, Hashable, Sendable, Codable {
    case train
    case flight
    case bus
    case stay
    case ticket
}
