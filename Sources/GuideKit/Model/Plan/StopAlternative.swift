/// A fallback place for a stop, and the reason it would be used.
public struct StopAlternative: Hashable, Sendable, Codable {
    public let placeId: String
    public let reason: AlternativeReason

    public init(placeId: String, reason: AlternativeReason) {
        self.placeId = placeId
        self.reason = reason
    }
}
