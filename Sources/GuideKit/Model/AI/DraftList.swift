/// A pick list in a plan: which candidate places it holds. Its title and caption come from the copy.
public struct DraftList: Hashable, Sendable, Codable {
    public let key: ListKey
    public let placeIds: [String]

    public init(key: ListKey, placeIds: [String]) {
        self.key = key
        self.placeIds = placeIds
    }
}
