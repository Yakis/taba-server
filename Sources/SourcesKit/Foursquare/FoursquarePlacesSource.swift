import Foundation
import FoursquareKit
import GuideKit

/// Finds candidate places by sweeping Foursquare categories around a centre.
///
/// Each kind is one search. Results are de-duplicated by Foursquare id across kinds, and closed places are skipped.
/// Hours are left unknown here: Foursquare's search does not return them. A website, when there is one, becomes a
/// fact whose source id is `sourceId`. The guide must hold a `Source` with that id.
public struct FoursquarePlacesSource: Sendable {
    public static let sourceId = "foursquare"

    /// Category ids by kind. These match the public list that FoursquareKit's `CategorySweeps` uses. `shop` is
    /// bakeries only.
    static let categoryTable: [PlaceKind: [String]] = [
        .cafe: ["63be6904847c3692a84b9bb6"],
        .pub: ["4bf58dd8d48988d11b941735"],
        .restaurant: ["4d4b7105d754a06374d81259"],
        .shop: ["4bf58dd8d48988d16a941735"],
        .viewpoint: ["4bf58dd8d48988d165941735"],
        .market: ["4bf58dd8d48988d1fa941735"],
        .museum: ["4bf58dd8d48988d181941735"],
        .grocery: ["4bf58dd8d48988d118951735"]
    ]

    /// What one kind's search did.
    public struct SweepOutcome: Sendable, Equatable {
        public let kind: PlaceKind
        /// How many places the search returned, before de-duplication and closed-place filtering.
        public let returned: Int
        /// Why the search failed, or nil when it worked.
        public let failure: String?
    }

    public struct SweepReport: Sendable, Equatable {
        public let places: [Place]
        public let sweeps: [SweepOutcome]
    }

    private let fetcher: any HTTPFetching
    private let builder: FoursquareRequestBuilder

    public init(fetcher: any HTTPFetching, apiKey: String) {
        self.fetcher = fetcher
        self.builder = FoursquareRequestBuilder(apiKey: apiKey)
    }

    /// Sweeps each kind around `centre`. A failed kind is reported and the others still run.
    public func sweep(
        kinds: [PlaceKind],
        around centre: Coordinate,
        radiusMetres: Int = 1500,
        limit: Int = 10,
        checkedAt: LocalDate
    ) async -> SweepReport {
        var places: [Place] = []
        var seenIds = Set<String>()
        var outcomes: [SweepOutcome] = []
        for kind in kinds {
            guard let categoryIds = Self.categoryTable[kind] else {
                outcomes.append(SweepOutcome(kind: kind, returned: 0, failure: "no Foursquare category for this kind"))
                continue
            }
            do {
                let hits = try await search(
                    categoryIds: categoryIds,
                    around: centre,
                    radiusMetres: radiusMetres,
                    limit: limit
                )
                for hit in hits where !Self.isClosed(hit) {
                    guard let place = Self.candidate(from: hit, checkedAt: checkedAt),
                          seenIds.insert(place.id).inserted
                    else {
                        continue
                    }
                    places.append(place)
                }
                outcomes.append(SweepOutcome(kind: kind, returned: hits.count, failure: nil))
            } catch {
                outcomes.append(SweepOutcome(kind: kind, returned: 0, failure: String(describing: error)))
            }
        }
        return SweepReport(places: places, sweeps: outcomes)
    }

    private func search(
        categoryIds: [String],
        around centre: Coordinate,
        radiusMetres: Int,
        limit: Int
    ) async throws -> [FoursquarePlace] {
        let parameters = SearchParameters(
            query: nil,
            latitude: centre.latitude,
            longitude: centre.longitude,
            radius: radiusMetres,
            categoryIds: categoryIds,
            limit: limit
        )
        let response = try await fetcher.send(builder.search(parameters))
        guard response.isSuccess else {
            throw SourcesError.http(status: response.status)
        }
        do {
            return try JSONDecoder().decode(FoursquareSearchResponse.self, from: response.body).results
        } catch {
            throw SourcesError.malformed("the Foursquare search response")
        }
    }

    static func isClosed(_ hit: FoursquarePlace) -> Bool {
        guard let closed = hit.dateClosed else { return false }
        return !closed.isEmpty
    }

    /// The draft place for one hit, with its website as a fact when there is one.
    static func candidate(from hit: FoursquarePlace, checkedAt: LocalDate) -> Place? {
        guard let draft = PlaceDraftMapper.draft(from: hit) else { return nil }
        let website = hit.website?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !website.isEmpty else { return draft }
        let fact = Fact(text: "Website: \(website)", sourceId: sourceId, checkedAt: checkedAt)
        return Place(
            id: draft.id,
            name: draft.name,
            kind: draft.kind,
            location: draft.location,
            hours: draft.hours,
            priceLevel: draft.priceLevel,
            booking: draft.booking,
            indoor: draft.indoor,
            images: draft.images,
            facts: [fact],
            copy: draft.copy
        )
    }
}
