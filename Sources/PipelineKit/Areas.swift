import Foundation
import GuideKit
import SourcesKit

/// One candidate and, if already looked up, its neighbourhood, suburb or quarter name.
/// Do not supply city or village fallback names: they obscure the local majority.
public struct AreaCandidate: Sendable, Equatable {
    public let id: String
    public let coordinate: Coordinate
    public let areaName: String?

    public init(id: String, coordinate: Coordinate, areaName: String? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.areaName = areaName
    }
}

/// A cluster's ID is its lexicographically first candidate ID, not its possibly shared name.
public struct AreaCluster: Sendable, Equatable {
    public let id: String
    /// Nil if none of the candidates had a local area name.
    public let name: String?
    public let candidateIDs: [String]
    public let centre: Coordinate
}

/// A directed measurement: a future walking provider may not be symmetric.
public struct AreaWalk: Sendable, Equatable {
    public let fromAreaID: String
    public let toAreaID: String
    public let minutes: Int
}

public struct Areas: Sendable, Equatable {
    public let clusters: [AreaCluster]
    /// Every ordered pair of distinct clusters, in cluster order. No same-area entries.
    public let walks: [AreaWalk]
}

public enum AreaClusteringError: Error, Sendable, Equatable {
    case duplicateCandidateID(String)
}

/// Deterministic complete-link clustering: a candidate joins the first cluster whose every member
/// is within 500 metres. Sorting by ID first makes the result independent of input order and prevents
/// chains of nearby points from growing into an arbitrarily large area.
public struct AreaClusterer: Sendable {
    public static let maximumDistanceMetres = 500.0
    private let walkTimes: any WalkTimes

    public init(walkTimes: any WalkTimes = StraightLineWalkTimes()) {
        self.walkTimes = walkTimes
    }

    /// Uses pre-resolved local area names; no network calls are made.
    public func cluster(_ candidates: [AreaCandidate]) throws -> Areas {
        let sorted = candidates.sorted { $0.id < $1.id }
        for index in sorted.indices.dropFirst() where sorted[index - 1].id == sorted[index].id {
            throw AreaClusteringError.duplicateCandidateID(sorted[index].id)
        }
        var groups: [[AreaCandidate]] = []
        for candidate in sorted {
            if let index = groups.firstIndex(where: { group in
                group.allSatisfy { distance($0.coordinate, candidate.coordinate) <= Self.maximumDistanceMetres }
            }) {
                groups[index].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
        let clusters = groups.map { group in
            AreaCluster(id: group[0].id, name: name(group), candidateIDs: group.map(\.id), centre: centre(group))
        }
        let walks = clusters.flatMap { from in
            clusters.filter { $0.id != from.id }.map { to in
                AreaWalk(
                    fromAreaID: from.id, toAreaID: to.id,
                    minutes: walkTimes.minutes(from: from.centre, to: to.centre)
                )
            }
        }
        return Areas(clusters: clusters, walks: walks)
    }

    /// Resolves each candidate using Nominatim's local-only area lookup, sequentially respecting its pacer.
    /// Lookup failures and cancellation are propagated. Existing names are replaced by lookup results.
    public func cluster(_ candidates: [AreaCandidate], geocoder: NominatimGeocoder) async throws -> Areas {
        try await cluster(candidates, resolveAreaName: {
            try await geocoder.areaName(near: $0, preferSuburbOrQuarter: true)
        })
    }

    /// Inject a local-only reverse lookup for testing or another provider. Return nil, not a city or village.
    public func cluster(
        _ candidates: [AreaCandidate],
        resolveAreaName: @Sendable (Coordinate) async throws -> String?
    ) async throws -> Areas {
        let sorted = candidates.sorted { $0.id < $1.id }
        for index in sorted.indices.dropFirst() where sorted[index - 1].id == sorted[index].id {
            throw AreaClusteringError.duplicateCandidateID(sorted[index].id)
        }
        var resolved: [AreaCandidate] = []
        for candidate in sorted {
            try Task.checkCancellation()
            let areaName = try await resolveAreaName(candidate.coordinate)
            resolved.append(AreaCandidate(id: candidate.id, coordinate: candidate.coordinate, areaName: areaName))
        }
        try Task.checkCancellation()
        return try cluster(resolved)
    }

    private func name(_ group: [AreaCandidate]) -> String? {
        var counts: [String: Int] = [:]
        for candidate in group {
            guard let raw = candidate.areaName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            counts[raw, default: 0] += 1
        }
        return counts.keys.sorted { left, right in
            let leftCount = counts[left, default: 0]
            let rightCount = counts[right, default: 0]
            return leftCount == rightCount ? left < right : leftCount > rightCount
        }.first
    }

    /// Average unit vectors so clusters straddling the antimeridian have the right centre.
    private func centre(_ group: [AreaCandidate]) -> Coordinate {
        var sumX = 0.0
        var sumY = 0.0
        var sumZ = 0.0
        for candidate in group {
            let latitude = candidate.coordinate.latitude * .pi / 180
            let longitude = candidate.coordinate.longitude * .pi / 180
            sumX += cos(latitude) * cos(longitude)
            sumY += cos(latitude) * sin(longitude)
            sumZ += sin(latitude)
        }
        let latitude = atan2(sumZ, hypot(sumX, sumY)) * 180 / .pi
        let longitude = atan2(sumY, sumX) * 180 / .pi
        // A group is nonempty and its points are within 500 m, so the mean is well-defined.
        return Coordinate(latitude: latitude, longitude: longitude) ?? group[0].coordinate
    }

    private func distance(_ first: Coordinate, _ second: Coordinate) -> Double {
        let latitude = (second.latitude - first.latitude) * .pi / 180
        let longitude = (second.longitude - first.longitude) * .pi / 180
        let firstLatitude = first.latitude * .pi / 180
        let secondLatitude = second.latitude * .pi / 180
        let chord = sin(latitude / 2) * sin(latitude / 2)
            + cos(firstLatitude) * cos(secondLatitude) * sin(longitude / 2) * sin(longitude / 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(chord)))
    }
}
