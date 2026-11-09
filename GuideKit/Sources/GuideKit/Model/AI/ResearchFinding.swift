/// One time-bound fact from research. The dates and times are the source's own, or nil when it says nothing.
public struct ResearchFinding: Hashable, Sendable, Codable {
    /// `f1`, `f2` and so on. Plans refer to a finding by this id.
    public let id: String
    public let kind: FindingKind
    public let title: String
    /// At most 40 words, in the research step's own words.
    public let summary: String
    public let startDate: LocalDate?
    public let endDate: LocalDate?
    public let times: String?
    public let placeName: String?
    public let address: String?
    public let url: String
    public let sourceTitle: String
    public let confidence: FindingConfidence
    /// True when the fact happens during the trip.
    public let onTripDates: Bool

    public init(
        id: String,
        kind: FindingKind,
        title: String,
        summary: String,
        startDate: LocalDate?,
        endDate: LocalDate?,
        times: String?,
        placeName: String?,
        address: String?,
        url: String,
        sourceTitle: String,
        confidence: FindingConfidence,
        onTripDates: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.startDate = startDate
        self.endDate = endDate
        self.times = times
        self.placeName = placeName
        self.address = address
        self.url = url
        self.sourceTitle = sourceTitle
        self.confidence = confidence
        self.onTripDates = onTripDates
    }
}
