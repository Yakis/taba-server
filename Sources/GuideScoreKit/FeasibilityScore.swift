import GuideKit

/// Whether the plan can happen as written: opening hours, stop lengths, walks between stops and the day's edges.
public struct FeasibilityScore: Codable, Sendable, Equatable {
    /// Stops whose place has no known opening hours.
    public let hoursUnknownStops: [String]
    /// Plan checker findings about hours, by kind.
    public let closedFindings: Int
    public let outsideHoursFindings: Int
    public let hoursUnknownFindings: Int
    /// Stops whose length is outside the range for their kind.
    public let durationsOutOfRange: [DurationIssue]
    /// Walks or rides between consecutive stops that take more than 30 minutes.
    public let longLegs: [LegIssue]
    /// The first stop's start and the last stop's end, per day.
    public let days: [DayEnds]
}

public struct DurationIssue: Codable, Sendable, Equatable {
    public let stopId: String
    public let kind: String
    public let minutes: Int
}

public struct LegIssue: Codable, Sendable, Equatable {
    public let fromStopId: String
    public let toStopId: String
    public let minutes: Int
}

public struct DayEnds: Codable, Sendable, Equatable {
    public let date: String
    /// "HH:MM", or nil for a day with no stops.
    public let firstStart: String?
    /// "HH:MM", or nil for a day with no stops.
    public let lastEnd: String?
}

extension FeasibilityScore {
    /// The lengths, in minutes, a stop of each kind may have. Travel and logistics are not checked.
    static let durationRanges: [StopKind: ClosedRange<Int>] = [
        .meal: 30...120, .drink: 20...120, .rest: 20...120, .sight: 15...240
    ]
    /// A leg longer than this is reported.
    static let longLegMinutes = 30

    static func make(_ context: GuideScoreContext) -> FeasibilityScore {
        let stops = context.guide.days.flatMap(\.stops)
        let byKind = Dictionary(grouping: context.findings, by: { $0.kind }).mapValues(\.count)
        return FeasibilityScore(
            hoursUnknownStops: stops.filter { context.place($0.placeId)?.hours.hoursKnown == false }.map(\.id),
            closedFindings: byKind[.closed] ?? 0,
            outsideHoursFindings: byKind[.outsideHours] ?? 0,
            hoursUnknownFindings: byKind[.hoursUnknown] ?? 0,
            durationsOutOfRange: stops.filter { outOfRange($0) }.map {
                DurationIssue(stopId: $0.id, kind: $0.kind.rawValue, minutes: $0.minutes)
            },
            longLegs: longLegs(context),
            days: context.days.map { dayEnds($0) }
        )
    }

    private static func outOfRange(_ stop: Stop) -> Bool {
        guard let range = durationRanges[stop.kind] else { return false }
        return !range.contains(stop.minutes)
    }

    private static func longLegs(_ context: GuideScoreContext) -> [LegIssue] {
        context.days.flatMap { day -> [LegIssue] in
            let placed = context.placedStops(day)
            return zip(placed, placed.dropFirst()).compactMap { pair in
                guard let leg = context.leg(pair.0, pair.1), leg.minutes > longLegMinutes else { return nil }
                return LegIssue(fromStopId: pair.0.id, toStopId: pair.1.id, minutes: leg.minutes)
            }
        }
    }

    private static func dayEnds(_ day: Day) -> DayEnds {
        DayEnds(
            date: day.date.description,
            firstStart: day.stops.map(\.start).min()?.description,
            lastEnd: day.stops.map { $0.start.minutesSinceMidnight + $0.minutes }.max().map(clockText)
        )
    }
}
