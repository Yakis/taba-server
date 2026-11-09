/// Why a stop has a fallback place.
public enum AlternativeReason: String, CaseIterable, Hashable, Sendable, Codable {
    case rain
    case closed
    case tired
}
