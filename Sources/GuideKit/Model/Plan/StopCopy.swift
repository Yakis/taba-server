/// The written title, body and optional button label for a stop.
public struct StopCopy: Hashable, Sendable, Codable {
    public let title: String
    public let body: String
    public let actionLabel: String?

    public init(title: String, body: String, actionLabel: String?) {
        self.title = title
        self.body = body
        self.actionLabel = actionLabel
    }
}
