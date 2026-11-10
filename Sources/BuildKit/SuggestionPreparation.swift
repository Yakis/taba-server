import Foundation
import FoursquareKit
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

public actor SuggestionPreparation {
    private let fetcher: CappedFetcher
    private let builder: FoursquareRequestBuilder
    private let initial: TripFacts
    private let record: SourceRecord
    private let geocoder: NominatimGeocoder
    /// How many research suggestions are looked up for one trip. Each is one Foursquare search.
    public static let maximumSuggestions = 12
    private var count = 0

    public init(fetcher: CappedFetcher, key: String, facts: TripFacts, record: SourceRecord,
                geocoder: NominatimGeocoder? = nil) {
        self.fetcher = fetcher
        self.builder = FoursquareRequestBuilder(apiKey: key)
        self.initial = facts
        self.record = record
        self.geocoder = geocoder ?? NominatimGeocoder(fetcher: fetcher)
    }

    public func resolve(_ suggestion: SuggestedPlace) async throws -> Place? {
        guard count < Self.maximumSuggestions else { return nil }
        count += 1
        let centre = initial.trip.destination.centre
        let matcher = PlaceMatcher(maxDistanceMetres: 10_000, cityName: initial.trip.destination.name)
        let wanted = WantedPlace(name: suggestion.name, kind: suggestion.kind, coordinate: centre)
        let seedHits = initial.places.values.compactMap { place -> FoursquarePlace? in
            guard place.kind == suggestion.kind else { return nil }
            let object: [String: Any] = ["fsq_place_id": place.id, "name": place.name,
                                         "latitude": place.location.coordinate.latitude,
                                         "longitude": place.location.coordinate.longitude]
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? JSONDecoder().decode(FoursquarePlace.self, from: data)
        }
        if let match = matcher.choose(for: wanted, among: seedHits).best,
           let place = initial.places[match.fsqPlaceId] {
            await record.append(["event": .string("suggestion"), "result": .string("existing"),
                                 "placeID": .string(place.id)])
            return place
        }
        let parameters = SearchParameters(query: suggestion.name,
            latitude: centre.latitude, longitude: centre.longitude, radius: 10_000, categoryIds: [], limit: 50)
        let start = ContinuousClock.now
        do {
            let response = try await fetcher.send(builder.search(parameters))
            try Task.checkCancellation()
            guard response.isSuccess else {
                await record.append(["event": .string("suggestion"), "status": .integer(response.status)])
                return nil
            }
            let hits = try JSONDecoder().decode(FoursquareSearchResponse.self, from: response.body).results
                .filter { $0.dateClosed?.isEmpty != false && !Self.isWrongAreaHit($0, for: suggestion.kind) }
            let decision = matcher.choose(for: wanted, among: hits)
            let hit = hits.first { $0.fsqPlaceId == decision.best?.fsqPlaceId }
            let place = hit.flatMap { PlaceDraftMapper.draft(from: $0) }
            await record.append(["event": .string("suggestion"),
                                 "result": .string(place == nil ? "unmatched" : "matched"),
                                 "hits": .integer(hits.count), "seconds": .number(seconds(start.duration(to: .now)))])
            return place
        } catch {
            try Task.checkCancellation()
            await record.append(["event": .string("suggestion"), "result": .string("failed")])
            return nil
        }
    }

    /// PlaceMatcher rejects road hits for food/retail; apply the same safeguard to sights here.
    private static func isWrongAreaHit(_ hit: FoursquarePlace, for kind: PlaceKind) -> Bool {
        guard kind != .street && kind != .neighbourhood && kind != .other else { return false }
        let areaWords: Set<String> = ["road", "roads", "street", "streets", "neighborhood", "neighborhoods",
                                      "neighbourhood", "neighbourhoods", "intersection", "intersections"]
        let hasArea = hit.categories.contains { category in
            category.name.lowercased().split(whereSeparator: { !$0.isLetter }).contains {
                areaWords.contains(String($0))
            }
        }
        return hasArea && !hit.categories.contains { PlaceKindMapper.kind(for: [$0]) == kind }
    }

    public func prepare(_ verified: VerifiedResearch, facts: TripFacts,
                        measurements: PipelineInputMeasurements) async throws
        -> (TripFacts, PipelineInputMeasurements) {
        let additions = verified.places.filter { facts.places[$0.id] == nil }
        guard !additions.isEmpty else { return (facts, measurements) }
        let start = ContinuousClock.now
        var places = facts.places
        var sources = facts.sources
        for place in additions { places[place.id] = place }
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: Date())
        guard let year = components.year, let month = components.month, let day = components.day,
              let today = LocalDate(year: year, month: month, day: day) else { throw SourcePreparationError.service }
        let lookup = await OverpassHoursSource(fetcher: fetcher).hours(for: additions.map {
            HoursLookupTarget(placeId: $0.id, name: $0.name, coordinate: $0.location.coordinate)
        }, cityName: facts.trip.destination.name, checkedAt: today)
        try Task.checkCancellation()
        await record.append(SourcePreparation.overpassEvent(lookup, seconds: seconds(start.duration(to: .now))))
        for result in lookup.results {
            guard case .found(let found) = result.outcome, let old = places[result.placeId] else { continue }
            places[old.id] = Place(id: old.id, name: old.name, kind: old.kind, location: old.location,
                hours: found.reading.hours, priceLevel: old.priceLevel, booking: old.booking, indoor: old.indoor,
                images: old.images, facts: old.facts, copy: old.copy)
            if !sources.contains(where: { $0.id == found.source.id }) { sources.append(found.source) }
        }
        if !sources.contains(where: { $0.id == FoursquarePlacesSource.sourceId }) {
            sources.append(Source(id: FoursquarePlacesSource.sourceId, url: "https://foursquare.com",
                                  title: "Foursquare", checkedAt: today))
        }
        let newFacts = TripFacts(trip: facts.trip, bookings: facts.bookings, stay: facts.stay, places: places,
                                 practical: facts.practical, sources: sources)
        let (updated, walks) = try await SourcePreparation.measure(newFacts, geocoder: geocoder,
                                                                   searchLabels: measurements.searchLabels)
        await record.append(["event": .string("suggestionPreparation"), "added": value(additions.map(\.id)),
                             "overpassUnavailable": .bool(lookup.error != nil),
                             "seconds": .number(seconds(start.duration(to: .now))), "places": value(places),
                             "sources": value(sources), "areas": value(updated.areas),
                             "searchLabels": value(updated.searchLabels),
                             "areaWalks": updated.areaWalkMinutes, "stayWalks": value(walks)])
        try await record.check()
        return (newFacts, updated)
    }

}
