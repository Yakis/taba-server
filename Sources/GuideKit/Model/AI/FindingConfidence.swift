/// How sure research is that a finding is right for the trip's year.
public enum FindingConfidence: String, CaseIterable, Hashable, Sendable, Codable {
    case high
    case medium
    case low
}
