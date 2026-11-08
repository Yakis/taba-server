/// A checked statement, tied to the source it came from and the date it was checked.
public struct Fact: Hashable, Sendable, Codable {
    public let text: String
    public let sourceId: String
    public let checkedAt: LocalDate

    public init(text: String, sourceId: String, checkedAt: LocalDate) {
        self.text = text
        self.sourceId = sourceId
        self.checkedAt = checkedAt
    }
}
