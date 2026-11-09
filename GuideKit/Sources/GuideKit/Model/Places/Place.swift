/// A place the guide can mention: a cafe, a viewpoint, a station, a hotel and so on.
public struct Place: Hashable, Sendable, Codable {
    /// Provider id such as "fsq:..." or "osm:...", or "manual:..." for hand-entered places.
    public let id: String
    public let name: String
    public let kind: PlaceKind
    public let location: PlaceLocation
    public let hours: OpeningHours
    /// 1 (cheapest) to 4 (most expensive). Omitted when unknown.
    public let priceLevel: Int?
    public let booking: PlaceBooking
    public let indoor: Bool
    public let images: [ImageRef]
    public let facts: [Fact]
    /// Written later by the AI. Omitted until then.
    public let copy: PlaceCopy?
    /// The place's own website, as a full "https://" address. Omitted when unknown.
    public let website: String?
    /// The phone number as the place publishes it, for example "+44 131 496 0000". Omitted when unknown.
    public let phone: String?

    public init(
        id: String,
        name: String,
        kind: PlaceKind,
        location: PlaceLocation,
        hours: OpeningHours,
        priceLevel: Int?,
        booking: PlaceBooking,
        indoor: Bool,
        images: [ImageRef],
        facts: [Fact],
        copy: PlaceCopy?,
        website: String? = nil,
        phone: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.location = location
        self.hours = hours
        self.priceLevel = priceLevel
        self.booking = booking
        self.indoor = indoor
        self.images = images
        self.facts = facts
        self.copy = copy
        self.website = website
        self.phone = phone
    }
}
