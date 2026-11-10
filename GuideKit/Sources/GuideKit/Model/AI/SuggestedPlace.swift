/// A place research suggests adding. Code looks it up in the places provider before anything can use it.
public struct SuggestedPlace: Hashable, Sendable, Codable {
    public let name: String
    public let area: String
    public let kind: PlaceKind
    /// At most 15 words.
    public let why: String
    /// The traveller's interests, as written in the trip, that this place serves. Nil in older research.
    public let interests: [String]?

    public init(name: String, area: String, kind: PlaceKind, why: String, interests: [String]? = nil) {
        self.name = name
        self.area = area
        self.kind = kind
        self.why = why
        self.interests = interests
    }
}
