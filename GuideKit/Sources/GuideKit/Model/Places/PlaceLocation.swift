/// Where a place is. `approximate` is true when the coordinate is only a rough area.
public struct PlaceLocation: Hashable, Sendable, Codable {
    public let coordinate: Coordinate
    public let address: String?
    public let approximate: Bool

    public init(coordinate: Coordinate, address: String?, approximate: Bool) {
        self.coordinate = coordinate
        self.address = address
        self.approximate = approximate
    }
}
