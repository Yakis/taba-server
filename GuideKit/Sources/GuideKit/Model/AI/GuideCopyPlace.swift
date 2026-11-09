/// The written tag and blurb for one place, keyed by place id.
public struct GuideCopyPlace: Hashable, Sendable, Codable {
    public let id: String
    public let tag: String
    public let blurb: String

    public init(id: String, tag: String, blurb: String) {
        self.id = id
        self.tag = tag
        self.blurb = blurb
    }
}
