/// Whether a place must be booked in advance, and where to do it.
public struct PlaceBooking: Hashable, Sendable, Codable {
    public let needed: Bool
    public let url: String?

    public init(needed: Bool, url: String?) {
        self.needed = needed
        self.url = url
    }
}
