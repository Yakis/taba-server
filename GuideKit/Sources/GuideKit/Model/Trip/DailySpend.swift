/// How much the travellers plan to spend on an ordinary day.
public enum DailySpend: String, CaseIterable, Hashable, Sendable, Codable {
    case low
    case moderate
    case high
}

extension DailySpend {
    /// The highest price level a plan uses on an ordinary day (plan.md rule 17): 2 for low, 3 for moderate, and nil for
    /// high, where any level fits.
    public var priceCeiling: Int? {
        switch self {
        case .low: 2
        case .moderate: 3
        case .high: nil
        }
    }
}
