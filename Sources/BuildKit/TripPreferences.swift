import GuideKit

/// The traveller's preferences for a trip. The pipeline reads them when it builds the trip scaffold.
public struct TripPreferences: Sendable, Hashable {
    public let pace: Pace
    /// Ranked interests, most important first.
    public let interests: [String]
    public let dailySpend: DailySpend
    public let adults: Int
    public let children: Int
    public let mobilityNotes: [String]

    public init(pace: Pace = .unhurried, interests: [String] = [], dailySpend: DailySpend = .moderate,
                adults: Int = 1, children: Int = 0, mobilityNotes: [String] = []) {
        self.pace = pace
        self.interests = interests
        self.dailySpend = dailySpend
        self.adults = adults
        self.children = children
        self.mobilityNotes = mobilityNotes
    }

    /// The values the pipeline used before preferences could be supplied.
    public static let standard = TripPreferences()

    public var party: Party {
        Party(adults: adults, children: children, mobilityNotes: mobilityNotes)
    }
}
