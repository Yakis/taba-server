/// What is known about a trip apart from its plan: the trip itself, the fixed bookings and stay, every place the guide
/// can mention, the practical facts and the sources they cite.
public struct TripFacts: Hashable, Sendable {
    public let trip: Trip
    public let bookings: [Booking]
    public let stay: Stay
    /// Every place the guide can mention, keyed by place id.
    public let places: [String: Place]
    public let practical: [Fact]
    public let sources: [Source]

    public init(
        trip: Trip,
        bookings: [Booking],
        stay: Stay,
        places: [String: Place],
        practical: [Fact],
        sources: [Source]
    ) {
        self.trip = trip
        self.bookings = bookings
        self.stay = stay
        self.places = places
        self.practical = practical
        self.sources = sources
    }
}
