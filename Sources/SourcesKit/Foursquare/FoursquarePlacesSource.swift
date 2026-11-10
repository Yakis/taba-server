import Foundation
import FoursquareKit
import GuideKit

/// Finds candidate places by sweeping Foursquare categories around a centre.
///
/// Each search is one Foursquare category search. Results are de-duplicated by Foursquare id across searches, and
/// closed places are skipped. Hours are left unknown here: Foursquare's search does not return them. A website, when
/// there is one, becomes a fact whose source id is `sourceId`. The guide must hold a `Source` with that id.
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
        .grocery: ["4bf58dd8d48988d118951735"],
        .venue: ["4bf58dd8d48988d1e5931735"]
    ]

    /// One search: a label for people and evidence, and the Foursquare category ids to search for.
    public struct CategorySearch: Sendable, Hashable {
        public let label: String
        public let categoryIds: [String]

        public init(label: String, categoryIds: [String]) {
            self.label = label
            self.categoryIds = categoryIds
        }
    }

    /// What one search did.
    public struct SweepOutcome: Sendable, Equatable {
        /// The search's label: a kind's raw value for `sweep(kinds:)`, or the label given to `sweep(searches:)`.
        public let label: String
        /// How many places the search returned, before de-duplication and closed-place filtering.
        public let returned: Int
        /// Why the search failed, or nil when it worked.
        public let failure: String?
        /// The ids of the places this search returned, after closed-place filtering. A place another search also
        /// returned is listed here too, so a search's places can be told apart from the others.
        public let placeIds: [String]
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

    /// One search per kind that has a Foursquare category, labelled with the kind's raw value. Kinds without a category
    /// are left out, so they are not searched.
    public static func searches(for kinds: [PlaceKind]) -> [CategorySearch] {
        kinds.compactMap { kind in
            categoryTable[kind].map { CategorySearch(label: kind.rawValue, categoryIds: $0) }
        }
    }

    /// Sweeps each kind around `centre`, one search per kind. A failed kind is reported and the others still run.
    public func sweep(
        kinds: [PlaceKind],
        around centre: Coordinate,
        radiusMetres: Int = 1500,
        limit: Int = 10,
        checkedAt: LocalDate
    ) async -> SweepReport {
        let requests = kinds.map { Request(label: $0.rawValue, categoryIds: Self.categoryTable[$0]) }
        return await run(requests, around: centre, radiusMetres: radiusMetres, limit: limit, checkedAt: checkedAt)
    }

    /// Runs each search around `centre`. A failed search is reported and the others still run.
    public func sweep(
        searches: [CategorySearch],
        around centre: Coordinate,
        radiusMetres: Int = 1500,
        limit: Int = 10,
        checkedAt: LocalDate
    ) async -> SweepReport {
        let requests = searches.map { Request(label: $0.label, categoryIds: $0.categoryIds) }
        return await run(requests, around: centre, radiusMetres: radiusMetres, limit: limit, checkedAt: checkedAt)
    }

    /// One search to run. `categoryIds` is nil when a kind has no Foursquare category, which is reported as a failure.
    private struct Request {
        let label: String
        let categoryIds: [String]?
    }

    private func run(
        _ requests: [Request],
        around centre: Coordinate,
        radiusMetres: Int,
        limit: Int,
        checkedAt: LocalDate
    ) async -> SweepReport {
        var places: [Place] = []
        var seenIds = Set<String>()
        var outcomes: [SweepOutcome] = []
        for request in requests {
            guard let categoryIds = request.categoryIds else {
                outcomes.append(SweepOutcome(label: request.label, returned: 0,
                                             failure: "no Foursquare category for this kind", placeIds: []))
                continue
            }
            do {
                let hits = try await search(
                    categoryIds: categoryIds,
                    around: centre,
                    radiusMetres: radiusMetres,
                    limit: limit
                )
                var returnedIds: [String] = []
                for hit in hits where !Self.isClosed(hit) {
                    guard let place = Self.candidate(from: hit, checkedAt: checkedAt) else { continue }
                    returnedIds.append(place.id)
                    if seenIds.insert(place.id).inserted {
                        places.append(place)
                    }
                }
                outcomes.append(SweepOutcome(label: request.label, returned: hits.count, failure: nil,
                                             placeIds: returnedIds))
            } catch {
                outcomes.append(SweepOutcome(label: request.label, returned: 0, failure: String(describing: error),
                                             placeIds: []))
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
