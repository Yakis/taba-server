/// A picture for a place, with its credit line.
public struct ImageRef: Hashable, Sendable, Codable {
    public let url: String
    public let credit: String

    public init(url: String, credit: String) {
        self.url = url
        self.credit = credit
    }
}
