import GuideKit

/// What every section of a score shares: the guide, the plan checker's findings (worked out once), and the walks and
/// legs between its stops. Built once per guide.
struct GuideScoreContext: Sendable {
    let guide: Guide
    let walkTimes: any WalkTimes
    let findings: [PlanIssue]

    init(guide: Guide, walkTimes: any WalkTimes) {
        self.guide = guide
        self.walkTimes = walkTimes
        self.findings = PlanChecker(walkTimes: walkTimes).check(guide)
    }

    /// The guide's days in date order.
    var days: [Day] {
        guide.days.sorted { $0.date < $1.date }
    }

    func place(_ id: String?) -> Place? {
        id.flatMap { guide.places[$0] }
    }

    /// The walk, or bus or taxi ride, between two stops. Nil unless both stops have places.
    func leg(_ first: Stop, _ second: Stop) -> Leg? {
        guard let origin = place(first.placeId), let destination = place(second.placeId) else { return nil }
        return Travel.leg(from: origin.location.coordinate, to: destination.location.coordinate, walkTimes: walkTimes)
    }

    /// The stops of a day that have a place, in time order. Walks run between consecutive ones.
    func placedStops(_ day: Day) -> [Stop] {
        day.stops.filter { $0.placeId != nil }.sorted { $0.start < $1.start }
    }

    /// A day's walking: the walk legs between consecutive placed stops, as `PaceChecks` sums them.
    func walkingMinutes(_ day: Day) -> Int {
        let placed = placedStops(day)
        return zip(placed, placed.dropFirst()).reduce(0) { sum, pair in
            guard let leg = leg(pair.0, pair.1), leg.mode == .walk else { return sum }
            return sum + leg.minutes
        }
    }

    /// Minutes in a day that no stop uses: each gap between one stop's end and the next start, less the travel
    /// between them, never below 0.
    func unplannedMinutes(_ day: Day) -> Int {
        let ordered = day.stops.sorted { $0.start < $1.start }
        return zip(ordered, ordered.dropFirst()).reduce(0) { sum, pair in
            let gap = pair.1.start.minutesSinceMidnight - (pair.0.start.minutesSinceMidnight + pair.0.minutes)
            let travel = leg(pair.0, pair.1)?.minutes ?? 0
            return sum + max(0, gap - travel)
        }
    }
}

extension Stop {
    /// Sights and drinks: the stops a day's pace counts. Meals, rests and logistics do not count.
    var isMainStop: Bool {
        kind == .sight || kind == .drink
    }
}

/// A ratio rounded to three decimal places, so the JSON is short and stable.
func thousandths(_ value: Double) -> Double {
    (value * 1000).rounded() / 1000
}

/// `numerator / denominator` as a fraction rounded to thousandths; 0 when the denominator is 0.
func fraction(_ numerator: Int, of denominator: Int) -> Double {
    denominator == 0 ? 0 : thousandths(Double(numerator) / Double(denominator))
}

/// "HH:MM" for minutes after midnight. Past 24:00 it wraps, so an after-midnight end shows as, say, "00:30".
func clockText(_ minutes: Int) -> String {
    LocalTime(minutesSinceMidnight: ((minutes % 1440) + 1440) % 1440)?.description ?? ""
}
