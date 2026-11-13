/// What the trip is: where, when, who, how much to spend, and how to write about it.
public struct Trip: Hashable, Sendable, Codable {
    public let destination: Destination
    public let dates: TripDates
    public let party: Party
    public let budget: Budget
    public let interests: [String]
    public let pace: Pace
    /// Free text describing the writing style.
    public let voice: String
    /// How the traveller gets there and back. Omitted when not said.
    public let travel: TripTravel?

    public init(
        destination: Destination,
        dates: TripDates,
        party: Party,
        budget: Budget,
        interests: [String],
        pace: Pace,
        voice: String,
        travel: TripTravel? = nil
    ) {
        self.destination = destination
        self.dates = dates
        self.party = party
        self.budget = budget
        self.interests = interests
        self.pace = pace
        self.voice = voice
        self.travel = travel
    }
}
