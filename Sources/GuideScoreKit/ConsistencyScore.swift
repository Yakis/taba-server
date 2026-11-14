import GuideKit
import PipelineKit

/// Whether the guide's parts refer to each other correctly: ids, pick lists, places that show nowhere, and sources.
public struct ConsistencyScore: Codable, Sendable, Equatable {
    /// Place ids in the pick lists that are not in `places`.
    public let listPlaceIdsMissing: [String]
    /// Place ids that stops use and that are not in `places`.
    public let stopPlaceIdsMissing: [String]
    /// Places in a pick list whose kind does not fit that list (`PlanChecker.listKinds`).
    public let listKindMismatches: [String]
    /// Places that nothing shows: no stop, pick list, stay, luggage, booking or trip travel point uses them. These are
    /// the spare candidates the guide carries, not a fault, so they are not counted as problems.
    public let unusedPlaceIds: [String]
    /// Source ids that practical facts cite but `sources` does not hold.
    public let practicalSourcesMissing: [String]

    /// How many problems were found, across every list above except the unused places.
    public var problemCount: Int {
        listPlaceIdsMissing.count + stopPlaceIdsMissing.count + listKindMismatches.count
            + practicalSourcesMissing.count
    }
}

extension ConsistencyScore {
    static func make(_ context: GuideScoreContext) -> ConsistencyScore {
        let guide = context.guide
        let stopPlaceIds = guide.days.flatMap(\.stops).compactMap(\.placeId)
        let sourceIds = Set(guide.sources.map(\.id))
        let referenced = referencedPlaceIds(guide)
        return ConsistencyScore(
            listPlaceIdsMissing: unique(guide.lists.flatMap(\.placeIds).filter { guide.places[$0] == nil }),
            stopPlaceIdsMissing: unique(stopPlaceIds.filter { guide.places[$0] == nil }),
            listKindMismatches: unique(guide.lists.flatMap { listMismatches($0, places: guide.places) }),
            unusedPlaceIds: guide.places.keys.filter { !referenced.contains($0) }.sorted(),
            practicalSourcesMissing: unique(guide.practical.map(\.sourceId).filter { !sourceIds.contains($0) })
        )
    }

    /// Every place id the guide shows somewhere: a stop (or its alternative), a pick list, the stay, the luggage
    /// store, a booking or the trip's travel points.
    private static func referencedPlaceIds(_ guide: Guide) -> Set<String> {
        var ids = Set(guide.days.flatMap(\.stops).flatMap { [$0.placeId, $0.alternative?.placeId] }.compactMap { $0 })
        ids.formUnion(guide.lists.flatMap(\.placeIds))
        ids.formUnion(guide.bookings.flatMap { [$0.fromPlaceId, $0.toPlaceId] }.compactMap { $0 })
        let stayAndTravel = [
            guide.stay.placeId, guide.stay.luggage?.placeId,
            guide.trip.travel?.arrivalPlaceId, guide.trip.travel?.departurePlaceId
        ]
        ids.formUnion(stayAndTravel.compactMap { $0 })
        return ids
    }

    private static func listMismatches(_ list: PlaceList, places: [String: Place]) -> [String] {
        guard let key = list.key, let allowed = PlanChecker.listKinds[key] else { return [] }
        return list.placeIds.filter { places[$0].map { !allowed.contains($0.kind) } == true }
    }

    /// The values with repeats removed, keeping the first of each.
    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
