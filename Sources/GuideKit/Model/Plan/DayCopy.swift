/// The written title and summary for a day.
public struct DayCopy: Hashable, Sendable, Codable {
    public let title: String
    public let summary: String

    public init(title: String, summary: String) {
        self.title = title
        self.summary = summary
    }
}
