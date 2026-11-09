/// The written title and summary for the day with this date.
public struct GuideCopyDay: Hashable, Sendable, Codable {
    public let date: LocalDate
    public let title: String
    public let summary: String

    public init(date: LocalDate, title: String, summary: String) {
        self.date = date
        self.title = title
        self.summary = summary
    }
}
