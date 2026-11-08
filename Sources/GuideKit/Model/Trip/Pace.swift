/// How full each day should feel.
public enum Pace: String, CaseIterable, Hashable, Sendable, Codable {
    case relaxed
    case unhurried
    case packed
}
