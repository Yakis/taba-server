/// Where the trip is. `timeZoneId` is an IANA identifier such as "Europe/London".
public struct Destination: Hashable, Sendable, Codable {
    public let name: String
    public let countryCode: String
    public let timeZoneId: String
    public let centre: Coordinate

    public init(name: String, countryCode: String, timeZoneId: String, centre: Coordinate) {
        self.name = name
        self.countryCode = countryCode
        self.timeZoneId = timeZoneId
        self.centre = centre
    }
}
