/// What kind of time-bound fact a research finding is.
public enum FindingKind: String, CaseIterable, Hashable, Sendable, Codable {
    case event
    case market
    case closure
    case transport
    case holiday
    case other
}
