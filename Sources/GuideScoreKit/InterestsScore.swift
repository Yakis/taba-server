import GuideKit
import PipelineKit

/// Where the stop-to-interest match comes from: the places' recorded `interests`, or the place kind when the guide
/// has none recorded (guides made before `Place.interests` existed).
public enum InterestSource: String, Codable, Sendable, Equatable {
    case recorded
    case kind
}

/// How the trip's ranked interests fare across the guide's stops.
public struct InterestsScore: Codable, Sendable, Equatable {
    public let source: InterestSource
    /// One row per trip interest, in rank order.
    public let byRank: [InterestScore]
    /// The fraction of adjacent rank pairs where the higher-ranked interest got at least as many main-stop minutes.
    /// 1 when there are fewer than two interests.
    public let rankAgreement: Double
    /// The largest single interest's share of all main-stop minutes. Shares can overlap, because one stop can serve
    /// two interests.
    public let topShare: Double
    /// Interests that no stop serves: main, meal and rest stops all count, travel and logistics do not.
    public let missed: [String]
}

/// What one trip interest got: its stops, minutes and first start.
public struct InterestScore: Codable, Sendable, Equatable {
    public let rank: Int
    public let name: String
    /// Sight and drink stops that serve the interest.
    public let mainStops: Int
    /// Meal stops that serve the interest.
    public let mealStops: Int
    /// Minutes at the main stops that serve the interest.
    public let minutes: Int
    /// `minutes` as a share of all main-stop minutes, from 0 to 1.
    public let share: Double
    /// The earliest start of any stop (main or meal) that serves the interest, as "HH:MM".
    public let earliestStart: String?
}

/// A stop with the trip interests its place serves.
struct ServedStop: Sendable {
    let stop: Stop
    let interests: [String]
}

extension InterestsScore {
    static func make(_ context: GuideScoreContext) -> InterestsScore {
        let guide = context.guide
        let trip = guide.trip.interests
        let source = InterestServing.source(of: guide)
        let served = guide.days.flatMap(\.stops).map { stop in
            ServedStop(stop: stop, interests: InterestServing.interests(
                context.place(stop.placeId), trip: trip, source: source))
        }
        let totalMinutes = served.filter { $0.stop.isMainStop }.reduce(0) { $0 + $1.stop.minutes }
        let rows = trip.enumerated().map { index, name in
            row(name, rank: index + 1, served: served, totalMinutes: totalMinutes)
        }
        return InterestsScore(
            source: source,
            byRank: rows,
            rankAgreement: rankAgreement(rows),
            topShare: rows.map(\.share).max() ?? 0,
            missed: trip.filter { name in
                !served.contains { $0.interests.contains(name) && ![.travel, .logistics].contains($0.stop.kind) }
            }
        )
    }

    private static func row(_ name: String, rank: Int, served: [ServedStop], totalMinutes: Int) -> InterestScore {
        let serving = served.filter { $0.interests.contains(name) }.map(\.stop)
        let main = serving.filter(\.isMainStop)
        let minutes = main.reduce(0) { $0 + $1.minutes }
        return InterestScore(
            rank: rank,
            name: name,
            mainStops: main.count,
            mealStops: serving.filter { $0.kind == .meal }.count,
            minutes: minutes,
            share: fraction(minutes, of: totalMinutes),
            earliestStart: serving.map(\.start).min()?.description
        )
    }

    /// Adjacent rank pairs (r, r+1) where rank r got at least as many minutes as rank r+1, as a fraction.
    private static func rankAgreement(_ rows: [InterestScore]) -> Double {
        guard rows.count >= 2 else { return 1 }
        let agreeing = zip(rows, rows.dropFirst()).filter { $0.minutes >= $1.minutes }.count
        return thousandths(Double(agreeing) / Double(rows.count - 1))
    }
}

/// Which trip interests a place serves, from its recorded interests or from its kind.
enum InterestServing {
    static func source(of guide: Guide) -> InterestSource {
        guide.places.values.contains { $0.interests != nil } ? .recorded : .kind
    }

    /// The trip's interests, in trip order, that the place serves. Nil places serve none.
    static func interests(_ place: Place?, trip: [String], source: InterestSource) -> [String] {
        guard let place else { return [] }
        switch source {
        case .recorded:
            let recorded = Set(place.interests ?? [])
            return trip.filter { recorded.contains($0) }
        case .kind:
            return InterestMatch.interests(for: trip, kind: place.kind, indoor: place.indoor, searchLabels: [])
        }
    }
}
