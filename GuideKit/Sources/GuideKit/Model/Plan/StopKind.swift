/// The kind of a stop.
public enum StopKind: String, CaseIterable, Hashable, Sendable, Codable {
    case sight
    case meal
    case drink
    case rest
    case travel
    case logistics
}
