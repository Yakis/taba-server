/// Where a guide is in its life cycle. `needsRecheck` means some facts may be out of date.
public enum GuideStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case draft
    case ready
    case needsRecheck
}
