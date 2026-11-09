/// The written copy for one stop, keyed by the plan's stop id.
public struct GuideCopyStop: Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let body: String
    /// A button label starting with a verb, or nil for a rest stop.
    public let actionLabel: String?

    public init(id: String, title: String, body: String, actionLabel: String?) {
        self.id = id
        self.title = title
        self.body = body
        self.actionLabel = actionLabel
    }
}
