import GuideKit

/// Two guides side by side: how far their plans overlap, and how each one spreads its minutes over the interests.
/// Made for the rank test: the same trip with its interests in another order should give a different plan.
public struct GuideComparison: Codable, Sendable, Equatable {
    /// Jaccard similarity of the main stops' place ids: 1 for the same places, 0 for none in common.
    public let visitedSimilarity: Double
    /// Jaccard similarity of every stop's place id.
    public let stopSimilarity: Double
    /// Each interest's main-stop minutes in both guides, in the order of the two trips' interests.
    public let interests: [InterestComparison]
    /// Interest names by minutes in the first guide, most first.
    public let orderA: [String]
    /// Interest names by minutes in the second guide, most first.
    public let orderB: [String]
}

public struct InterestComparison: Codable, Sendable, Equatable {
    public let name: String
    public let minutesA: Int
    public let minutesB: Int
}

extension GuideScorer {
    /// Compares two guides. Interests are matched by their name, ignoring case.
    public static func compare(
        _ first: Guide, _ second: Guide, walkTimes: any WalkTimes = StraightLineWalkTimes()
    ) -> GuideComparison {
        let scoreA = score(first, walkTimes: walkTimes)
        let scoreB = score(second, walkTimes: walkTimes)
        let names = unionNames(scoreA.interests.byRank.map(\.name), scoreB.interests.byRank.map(\.name))
        let minutesA = { (name: String) in minutes(scoreA, name) }
        let minutesB = { (name: String) in minutes(scoreB, name) }
        return GuideComparison(
            visitedSimilarity: jaccard(placeIds(first, mainOnly: true), placeIds(second, mainOnly: true)),
            stopSimilarity: jaccard(placeIds(first, mainOnly: false), placeIds(second, mainOnly: false)),
            interests: names.map { InterestComparison(name: $0, minutesA: minutesA($0), minutesB: minutesB($0)) },
            orderA: order(names, by: minutesA),
            orderB: order(names, by: minutesB)
        )
    }

    /// The place ids of the guide's stops: only the main stops when `mainOnly` is true.
    static func placeIds(_ guide: Guide, mainOnly: Bool) -> Set<String> {
        let stops = guide.days.flatMap(\.stops)
        return Set(stops.filter { !mainOnly || $0.isMainStop }.compactMap(\.placeId))
    }

    /// Jaccard similarity: the common items over all items. Two empty sets are the same, so 1.
    static func jaccard(_ first: Set<String>, _ second: Set<String>) -> Double {
        let union = first.union(second).count
        guard union > 0 else { return 1 }
        return thousandths(Double(first.intersection(second).count) / Double(union))
    }

    /// The first list, then the names of the second that the first does not have, ignoring case.
    static func unionNames(_ first: [String], _ second: [String]) -> [String] {
        var names = first
        for name in second where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    private static func minutes(_ score: GuideScore, _ name: String) -> Int {
        score.interests.byRank.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.minutes ?? 0
    }

    /// The names by minutes, most first. Ties keep their order in `names`.
    private static func order(_ names: [String], by minutes: (String) -> Int) -> [String] {
        names.enumerated().sorted { lhs, rhs in
            let (left, right) = (minutes(lhs.element), minutes(rhs.element))
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
