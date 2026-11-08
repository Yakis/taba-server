/// The written title and caption for one pick list, keyed by the list's key.
public struct GuideCopyList: Hashable, Sendable, Codable {
    public let key: ListKey
    public let title: String
    public let caption: String

    public init(key: ListKey, title: String, caption: String) {
        self.key = key
        self.title = title
        self.caption = caption
    }
}
