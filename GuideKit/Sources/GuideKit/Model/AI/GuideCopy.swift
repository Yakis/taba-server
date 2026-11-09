/// What the writer returns: every word of the guide, for a checked plan. Every id must match the plan's ids, and
/// no others.
public struct GuideCopy: Hashable, Sendable, Codable {
    public let hero: GuideHero
    public let days: [GuideCopyDay]
    public let stops: [GuideCopyStop]
    public let places: [GuideCopyPlace]
    public let lists: [GuideCopyList]
    public let tasting: [TasteItem]
    public let notes: GuideNotes

    public init(
        hero: GuideHero,
        days: [GuideCopyDay],
        stops: [GuideCopyStop],
        places: [GuideCopyPlace],
        lists: [GuideCopyList],
        tasting: [TasteItem],
        notes: GuideNotes
    ) {
        self.hero = hero
        self.days = days
        self.stops = stops
        self.places = places
        self.lists = lists
        self.tasting = tasting
        self.notes = notes
    }
}
