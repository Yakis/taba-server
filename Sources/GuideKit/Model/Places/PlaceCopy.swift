/// The short written tag and blurb for a place.
public struct PlaceCopy: Hashable, Sendable, Codable {
    public let tag: String
    public let blurb: String

    public init(tag: String, blurb: String) {
        self.tag = tag
        self.blurb = blurb
    }
}
