/// What research returns for one trip: time-bound facts for the exact dates, each with its source, and places a
/// places database may have missed. Code drops any finding whose URL was not in the search results.
public struct ResearchResult: Hashable, Sendable, Codable {
    public let findings: [ResearchFinding]
    public let suggestedPlaces: [SuggestedPlace]
    /// One or two sentences on what could not be confirmed.
    public let searchNotes: String

    public init(findings: [ResearchFinding], suggestedPlaces: [SuggestedPlace], searchNotes: String) {
        self.findings = findings
        self.suggestedPlaces = suggestedPlaces
        self.searchNotes = searchNotes
    }
}
