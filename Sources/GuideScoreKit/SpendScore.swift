import GuideKit

/// The price levels of the stops against the trip's daily spend.
public struct SpendScore: Codable, Sendable, Equatable {
    public let dailySpend: String
    /// The highest price level the plan should use (plan.md rule 17): 2 for low, 3 for moderate, and nil for high,
    /// where any level fits.
    public let ceiling: Int?
    /// Meal and drink stops.
    public let mealAndDrink: SpendCount
    /// Sight stops.
    public let sights: SpendCount
}

/// How many stops sit at each price level, and which of them are above the ceiling.
public struct SpendCount: Codable, Sendable, Equatable {
    /// Stops by their place's price level: "1" to "4", and "unknown" when the place has none or the stop has no place.
    public let byLevel: [String: Int]
    /// The ids of the stops above the ceiling.
    public let aboveCeiling: [String]
}

extension SpendScore {
    static func make(_ context: GuideScoreContext) -> SpendScore {
        let spend = context.guide.trip.budget.dailySpend
        let ceiling = ceiling(for: spend)
        let stops = context.guide.days.flatMap(\.stops)
        return SpendScore(
            dailySpend: spend.rawValue,
            ceiling: ceiling,
            mealAndDrink: count(stops.filter { [.meal, .drink].contains($0.kind) }, ceiling: ceiling, context),
            sights: count(stops.filter { $0.kind == .sight }, ceiling: ceiling, context)
        )
    }

    /// The highest price level each daily spend allows, from plan.md rule 17.
    static func ceiling(for spend: DailySpend) -> Int? {
        switch spend {
        case .low: 2
        case .moderate: 3
        case .high: nil
        }
    }

    private static func count(_ stops: [Stop], ceiling: Int?, _ context: GuideScoreContext) -> SpendCount {
        var byLevel: [String: Int] = ["1": 0, "2": 0, "3": 0, "4": 0, "unknown": 0]
        var above: [String] = []
        for stop in stops {
            let level = context.place(stop.placeId)?.priceLevel
            byLevel[level.map(String.init) ?? "unknown", default: 0] += 1
            if let level, let ceiling, level > ceiling {
                above.append(stop.id)
            }
        }
        return SpendCount(byLevel: byLevel, aboveCeiling: above)
    }
}
