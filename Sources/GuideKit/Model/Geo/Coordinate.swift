/// A latitude and longitude, written as {"latitude": ..., "longitude": ...}.
public struct Coordinate: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    /// Returns nil unless latitude is in -90...90 and longitude is in -180...180.
    public init?(latitude: Double, longitude: Double) {
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        guard let coordinate = Coordinate(latitude: latitude, longitude: longitude) else {
            throw DecodingError.dataCorruptedError(
                forKey: .latitude,
                in: container,
                debugDescription: "Coordinate out of range: latitude must be -90...90, longitude -180...180"
            )
        }
        self = coordinate
    }
}
