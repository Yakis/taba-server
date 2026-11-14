import GuideKit

/// How full each day is, against the pace the traveller chose.
public struct PaceScore: Codable, Sendable, Equatable {
    public let pace: String
    public let target: PaceTarget
    /// Every day, in date order.
    public let days: [DayPace]
}

/// The pace table from the planning prompt (plan.md rule 10), for reference next to the measured days.
public struct PaceTarget: Codable, Sendable, Equatable {
    public let mainStopsMin: Int
    /// Nil when there is no upper limit.
    public let mainStopsMax: Int?
    /// The earliest start of the first main stop, as "HH:MM". Nil when there is no limit.
    public let firstStartNotBefore: String?
    /// The walking the day is planned around. `PlanChecker` warns above 1.2 times this.
    public let walkingMinutes: Int

    static func of(_ pace: Pace) -> PaceTarget {
        switch pace {
        case .relaxed:
            PaceTarget(mainStopsMin: 3, mainStopsMax: 4, firstStartNotBefore: "09:30",
                       walkingMinutes: pace.walkingLimitMinutes)
        case .unhurried:
            PaceTarget(mainStopsMin: 4, mainStopsMax: 5, firstStartNotBefore: "09:00",
                       walkingMinutes: pace.walkingLimitMinutes)
        case .packed:
            PaceTarget(mainStopsMin: 6, mainStopsMax: nil, firstStartNotBefore: nil,
                       walkingMinutes: pace.walkingLimitMinutes)
        }
    }
}

/// One day measured against the pace.
public struct DayPace: Codable, Sendable, Equatable {
    public let date: String
    /// False on the arrival and departure days and on a one-day trip. Only full days are judged against the pace.
    public let fullDay: Bool
    public let mainStops: Int
    public let firstMainStart: String?
    public let walkingMinutes: Int
    public let restStops: Int
    public let restMinutes: Int
    /// Gaps between stops that no stop uses, less the travel between them.
    public let unplannedMinutes: Int
    public let withinTarget: TargetCheck
}

/// Whether a day meets the pace target on main stops and on walking.
public struct TargetCheck: Codable, Sendable, Equatable {
    public let mainStops: Bool
    public let walking: Bool
}

extension PaceScore {
    static func make(_ context: GuideScoreContext) -> PaceScore {
        let pace = context.guide.trip.pace
        let target = PaceTarget.of(pace)
        let days = context.days.map { dayPace($0, context: context, target: target) }
        return PaceScore(pace: pace.rawValue, target: target, days: days)
    }

    private static func dayPace(_ day: Day, context: GuideScoreContext, target: PaceTarget) -> DayPace {
        let trip = context.guide.trip.dates
        let main = day.stops.filter(\.isMainStop).sorted { $0.start < $1.start }
        let rests = day.stops.filter { $0.kind == .rest }
        let walking = context.walkingMinutes(day)
        let withinCount = main.count >= target.mainStopsMin
            && target.mainStopsMax.map { main.count <= $0 } ?? true
        return DayPace(
            date: day.date.description,
            fullDay: day.date != trip.start && day.date != trip.end,
            mainStops: main.count,
            firstMainStart: main.first?.start.description,
            walkingMinutes: walking,
            restStops: rests.count,
            restMinutes: rests.reduce(0) { $0 + $1.minutes },
            unplannedMinutes: context.unplannedMinutes(day),
            withinTarget: TargetCheck(mainStops: withinCount, walking: walking <= target.walkingMinutes)
        )
    }
}
