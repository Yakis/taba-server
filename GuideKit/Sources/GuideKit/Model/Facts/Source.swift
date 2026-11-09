/// A web page or document that facts were checked against.
public struct Source: Hashable, Sendable, Codable {
    public let id: String
    public let url: String
    public let title: String
    public let checkedAt: LocalDate

    public init(id: String, url: String, title: String, checkedAt: LocalDate) {
        self.id = id
        self.url = url
        self.title = title
        self.checkedAt = checkedAt
    }
}
