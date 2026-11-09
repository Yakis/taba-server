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
    /// The title block. Omitted until the copy is written.
    public let hero: GuideHero?
    /// Practical notes for the trip. Omitted until the copy is written.
    public let notes: GuideNotes?
    /// Things the traveller should check or decide. Omitted when there are none.
    public let openQuestions: [String]?
    /// The AI model that wrote this guide, as the provider names it, such as gpt-6.1-terra. Omitted for guides
    /// made before this was recorded.
    public let aiModel: String?

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
        sources: [Source],
        hero: GuideHero? = nil,
        notes: GuideNotes? = nil,
        openQuestions: [String]? = nil,
        aiModel: String? = nil
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
        self.hero = hero
        self.notes = notes
        self.openQuestions = openQuestions
        self.aiModel = aiModel
    }
}
