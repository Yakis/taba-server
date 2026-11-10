import Foundation
import FoursquareKit
import GuideKit

/// The place a search is looking for.
public struct WantedPlace: Sendable, Equatable {
    public let name: String
    public let kind: PlaceKind
    public let coordinate: Coordinate

    public init(name: String, kind: PlaceKind, coordinate: Coordinate) {
        self.name = name
        self.kind = kind
        self.coordinate = coordinate
    }
}

/// A hit that could be the wanted place. `score` is 75% name similarity and 25% nearness.
public struct PlaceMatch: Sendable, Equatable {
    public let fsqPlaceId: String
    public let name: String
    public let distanceMetres: Double
    public let nameSimilarity: Double
    public let score: Double
}

/// A hit that was not chosen, and why.
public struct RejectedHit: Sendable, Equatable {
    public let fsqPlaceId: String
    public let name: String
    public let reason: String
}

public struct MatchDecision: Sendable, Equatable {
    /// The chosen hit, or nil when no hit is the wanted place.
    public let best: PlaceMatch?
    public let rejected: [RejectedHit]
}

/// Chooses which of several Foursquare search hits is the wanted place.
///
/// A hit is thrown out when it is too far away, when its categories are a road, street or neighbourhood for a place
/// that is a restaurant, pub, cafe or shop, when its categories are all shops for a market or food hall, or when its
/// name shares too few significant words. The rest are ranked by name similarity and distance.
public struct PlaceMatcher: Sendable {
    public let maxDistanceMetres: Double
    public let cityName: String?

    /// Kinds of place where a road, street or neighbourhood hit is never the place itself.
    static let shopLikeKinds: Set<PlaceKind> = [.cafe, .restaurant, .pub, .bar, .shop, .foodHall, .grocery, .market]
    /// Category words for a road or area rather than a place.
    static let areaCategoryWords: Set<String> = [
        "road", "roads", "street", "streets", "neighborhood", "neighborhoods",
        "neighbourhood", "neighbourhoods", "intersection", "intersections"
    ]
    /// Kinds of place that a shop is never. A hit whose categories are all shops is rejected for these kinds. The
    /// value is the words used in the rejection reason.
    static let marketKinds: [PlaceKind: String] = [.market: "market", .foodHall: "food hall"]

    public init(maxDistanceMetres: Double = 200, cityName: String? = nil) {
        self.maxDistanceMetres = maxDistanceMetres
        self.cityName = cityName
    }

    public func choose(for wanted: WantedPlace, among hits: [FoursquarePlace]) -> MatchDecision {
        var rejected: [RejectedHit] = []
        var matches: [PlaceMatch] = []
        for hit in hits {
            switch evaluate(hit, for: wanted) {
            case .rejected(let reason):
                rejected.append(RejectedHit(fsqPlaceId: hit.fsqPlaceId, name: hit.name, reason: reason))
            case .matched(let match):
                matches.append(match)
            }
        }
        let best = matches.reduce(nil as PlaceMatch?) { current, candidate in
            guard let current else { return candidate }
            return isBetter(candidate, than: current) ? candidate : current
        }
        for match in matches where match != best {
            rejected.append(RejectedHit(
                fsqPlaceId: match.fsqPlaceId,
                name: match.name,
                reason: "ranked below the chosen hit"
            ))
        }
        return MatchDecision(best: best, rejected: rejected)
    }

    private enum Verdict {
        case rejected(String)
        case matched(PlaceMatch)
    }

    private func evaluate(_ hit: FoursquarePlace, for wanted: WantedPlace) -> Verdict {
        guard let latitude = hit.latitude, let longitude = hit.longitude,
              let point = Coordinate(latitude: latitude, longitude: longitude)
        else {
            return .rejected("no coordinate")
        }
        let distance = Geo.metres(from: wanted.coordinate, to: point)
        guard distance <= maxDistanceMetres else {
            return .rejected("\(Int(distance.rounded())) m away, over the \(Int(maxDistanceMetres)) m limit")
        }
        if Self.shopLikeKinds.contains(wanted.kind), isAreaOnly(hit, for: wanted.kind) {
            return .rejected("category is a road or area, not a \(wanted.kind.rawValue)")
        }
        if let kindName = Self.marketKinds[wanted.kind], isShopOnly(hit) {
            return .rejected("a shop, not a \(kindName)")
        }
        let similarity = NameTokens.nameSimilarity(wanted.name, hit.name, cityName: cityName)
        guard similarity >= NameTokens.acceptableSimilarity else {
            return .rejected("name similarity \(String(format: "%.2f", similarity)) is too low")
        }
        let nearness = max(0, 1 - distance / maxDistanceMetres)
        let score = 0.75 * similarity + 0.25 * nearness
        return .matched(PlaceMatch(
            fsqPlaceId: hit.fsqPlaceId,
            name: hit.name,
            distanceMetres: distance,
            nameSimilarity: similarity,
            score: score
        ))
    }

    /// True when a category is a road or area word and no category maps to the wanted kind.
    private func isAreaOnly(_ hit: FoursquarePlace, for kind: PlaceKind) -> Bool {
        let hasAreaCategory = hit.categories.contains { category in
            NameTokens.words(in: category.name).contains { Self.areaCategoryWords.contains($0) }
        }
        guard hasAreaCategory else { return false }
        return !hit.categories.contains { PlaceKindMapper.kind(for: [$0]) == kind }
    }

    /// True when the hit has categories and every one of them maps to a shop. A hit with no categories is not
    /// judged a shop, because nothing says what it is.
    private func isShopOnly(_ hit: FoursquarePlace) -> Bool {
        guard !hit.categories.isEmpty else { return false }
        return hit.categories.allSatisfy { PlaceKindMapper.kind(for: [$0]) == .shop }
    }

    private func isBetter(_ candidate: PlaceMatch, than current: PlaceMatch) -> Bool {
        if candidate.score != current.score {
            return candidate.score > current.score
        }
        return candidate.distanceMetres < current.distanceMetres
    }
}
