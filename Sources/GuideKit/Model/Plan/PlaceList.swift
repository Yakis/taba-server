/// A named, ordered selection of places, such as "Coffee" or "Rainy-day options".
public struct PlaceList: Hashable, Sendable, Codable {
    public let title: String
    public let caption: String
    public let placeIds: [String]
    /// The plan's key for the list (`eat`, `drink`, ...). Omitted for lists that were not made from a plan.
    public let key: ListKey?

    public init(title: String, caption: String, placeIds: [String], key: ListKey? = nil) {
        self.title = title
        self.caption = caption
        self.placeIds = placeIds
        self.key = key
    }
}
