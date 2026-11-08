/// A named, ordered selection of places, such as "Coffee" or "Rainy-day options".
public struct PlaceList: Hashable, Sendable, Codable {
    public let title: String
    public let caption: String
    public let placeIds: [String]

    public init(title: String, caption: String, placeIds: [String]) {
        self.title = title
        self.caption = caption
        self.placeIds = placeIds
    }
}
