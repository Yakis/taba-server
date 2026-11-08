/// A complete walking field guide for one trip.
public struct Guide: Hashable, Sendable, Codable {
    public let id: String
    public let version: Int
    public let status: GuideStatus
    public let trip: Trip
    public let bookings: [Booking]
    public let stay: Stay
    /// Every place the guide mentions, keyed by place id. Each key must equal its place's `id`.
    public let places: [String: Place]
    public let days: [Day]
    public let lists: [PlaceList]
    public let tasting: [TasteItem]
    public let practical: [Fact]
    public let sources: [Source]

    public init(
        id: String,
        version: Int,
        status: GuideStatus,
        trip: Trip,
        bookings: [Booking],
        stay: Stay,
        places: [String: Place],
        days: [Day],
        lists: [PlaceList],
        tasting: [TasteItem],
        practical: [Fact],
        sources: [Source]
    ) {
        self.id = id
        self.version = version
        self.status = status
        self.trip = trip
        self.bookings = bookings
        self.stay = stay
        self.places = places
        self.days = days
        self.lists = lists
        self.tasting = tasting
        self.practical = practical
        self.sources = sources
    }
}
