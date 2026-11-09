/// The title block at the top of the guide.
public struct GuideHero: Hashable, Sendable, Codable {
    public let title: String
    public let subtitle: String
    public let tagline: String

    public init(title: String, subtitle: String, tagline: String) {
        self.title = title
        self.subtitle = subtitle
        self.tagline = tagline
    }
}
