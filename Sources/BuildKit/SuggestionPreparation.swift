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
    private let openStreetMap: OpenStreetMapFallback
    /// How many research suggestions are looked up for one trip. Each is one Foursquare search, or one OpenStreetMap
    /// lookup once Foursquare has failed.
    public static let maximumSuggestions = 12
    private var count = 0
    /// Set when a Foursquare search fails. Later suggestions then go straight to OpenStreetMap.
    private var foursquareFailed = false

    public init(fetcher: CappedFetcher, key: String, facts: TripFacts, record: SourceRecord,
                geocoder: NominatimGeocoder? = nil) {
        self.init(fetcher: fetcher, key: key, facts: facts, record: record, geocoder: geocoder,
                  openStreetMap: OpenStreetMapFallback(fetcher: fetcher))
    }

    init(fetcher: CappedFetcher, key: String, facts: TripFacts, record: SourceRecord,
         geocoder: NominatimGeocoder?, openStreetMap: OpenStreetMapFallback) {
        self.fetcher = fetcher
        self.builder = FoursquareRequestBuilder(apiKey: key)
        self.initial = facts
        self.record = record
        self.geocoder = geocoder ?? NominatimGeocoder(fetcher: fetcher)
        self.openStreetMap = openStreetMap
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
        if foursquareFailed {
            return try await resolveWithOpenStreetMap(suggestion, centre: centre)
        }
        let parameters = SearchParameters(query: suggestion.name,
            latitude: centre.latitude, longitude: centre.longitude, radius: 10_000, categoryIds: [], limit: 50)
        let start = ContinuousClock.now
        let answer: [FoursquarePlace]
        do {
            answer = try await searchFoursquare(parameters)
        } catch {
            try Task.checkCancellation()
            await record.append(["event": .string("suggestion"), "result": .string("failed")])
            foursquareFailed = true
            return try await resolveWithOpenStreetMap(suggestion, centre: centre)
        }
        let hits = answer.filter { $0.dateClosed?.isEmpty != false && !Self.isWrongAreaHit($0, for: suggestion.kind) }
        let decision = matcher.choose(for: wanted, among: hits)
        let hit = hits.first { $0.fsqPlaceId == decision.best?.fsqPlaceId }
        let place = hit.flatMap { PlaceDraftMapper.draft(from: $0) }
            .map { Self.keepingSuggestedKind($0, suggested: suggestion.kind) }
        await record.append(["event": .string("suggestion"),
                             "result": .string(place == nil ? "unmatched" : "matched"),
                             "hits": .integer(hits.count), "seconds": .number(seconds(start.duration(to: .now)))])
        return place
    }

    /// One Foursquare search. A reply other than 2xx is recorded and thrown, as is a malformed body.
    private func searchFoursquare(_ parameters: SearchParameters) async throws -> [FoursquarePlace] {
        let response = try await fetcher.send(builder.search(parameters))
        try Task.checkCancellation()
        guard response.isSuccess else {
            await record.append(["event": .string("suggestion"), "status": .integer(response.status)])
            throw SourcesError.http(status: response.status)
        }
        return try JSONDecoder().decode(FoursquareSearchResponse.self, from: response.body).results
    }

    /// The OpenStreetMap lookup for a suggestion, used once Foursquare has failed. It matches by name, within 10 km.
    /// Nominatim is asked first, as it is fast and reliable for names. Overpass is asked only when Nominatim fails; a
    /// Nominatim answer with no match is final.
    private func resolveWithOpenStreetMap(_ suggestion: SuggestedPlace, centre: Coordinate) async throws -> Place? {
        guard let today = Self.today() else { throw SourcePreparationError.service }
        let city = initial.trip.destination.name
        let nominatimStart = ContinuousClock.now
        let nominatim = await openStreetMap.nominatim.find(named: suggestion.name, near: centre, cityName: city,
                                                           checkedAt: today)
        try Task.checkCancellation()
        switch nominatim {
        case .success(let found):
            return await recordOpenStreetMapMatch(found, source: "nominatim", suggested: suggestion.kind,
                                                  start: nominatimStart)
        case .failure:
            await recordOpenStreetMapFailure(source: "nominatim", start: nominatimStart)
        }
        let overpassStart = ContinuousClock.now
        let overpass = await openStreetMap.overpass.find(named: suggestion.name, near: centre, cityName: city,
                                                         checkedAt: today)
        try Task.checkCancellation()
        switch overpass {
        case .success(let found):
            return await recordOpenStreetMapMatch(found, source: "osm", suggested: suggestion.kind,
                                                  start: overpassStart)
        case .failure:
            await recordOpenStreetMapFailure(source: "osm", start: overpassStart)
            return nil
        }
    }

    /// Records a lookup that answered, matched or not, and returns the place with the suggested kind.
    private func recordOpenStreetMapMatch(_ found: Place?, source: String, suggested: PlaceKind,
                                          start: ContinuousClock.Instant) async -> Place? {
        let place = found.map { Self.keepingSuggestedKind($0, suggested: suggested) }
        await record.append(["event": .string("suggestion"), "source": .string(source),
                             "result": .string(place == nil ? "unmatched" : "matched"),
                             "seconds": .number(seconds(start.duration(to: .now)))])
        return place
    }

    private func recordOpenStreetMapFailure(source: String, start: ContinuousClock.Instant) async {
        await record.append(["event": .string("suggestion"), "source": .string(source),
                             "result": .string("failed"), "seconds": .number(seconds(start.duration(to: .now)))])
    }

    /// Today's date in GMT, as the trip dates are compared with it.
    static func today() -> LocalDate? {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: Date())
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return LocalDate(year: year, month: month, day: day)
    }

    /// Research says what a suggested place is. Foursquare often files a street or a hill under another kind ("other",
    /// "landmark"), and indoor follows the kind, so the place could be taken for indoors. A suggested street,
    /// neighbourhood or viewpoint keeps its own kind and is outdoors when Foursquare gave it "other" or "landmark".
    /// Every other place comes back as it is.
    static func keepingSuggestedKind(_ place: Place, suggested: PlaceKind) -> Place {
        let outdoorKinds: Set<PlaceKind> = [.street, .neighbourhood, .viewpoint]
        guard outdoorKinds.contains(suggested), [PlaceKind.other, .landmark].contains(place.kind) else { return place }
        return Place(id: place.id, name: place.name, kind: suggested, location: place.location, hours: place.hours,
                     priceLevel: place.priceLevel, booking: place.booking, indoor: false, images: place.images,
                     facts: place.facts, copy: place.copy, website: place.website, phone: place.phone)
    }

    /// The measured search labels with each suggested place's interests added to its place, as "interest:<interest>"
    /// (see `InterestMatch.interestLabel`). Labels the place already has are kept, with no duplicates, and sorted like
    /// the interest searches. Only the places research suggested for an interest get a label.
    static func withInterestLabels(_ measurements: PipelineInputMeasurements, _ verified: VerifiedResearch)
        -> PipelineInputMeasurements {
        var labels = measurements.searchLabels
        for (suggestion, place) in zip(verified.result.suggestedPlaces, verified.places) {
            let added = (suggestion.interests ?? [])
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { InterestMatch.interestLabel(for: $0) }
            guard !added.isEmpty else { continue }
            labels[place.id] = Array(Set((labels[place.id] ?? []) + added)).sorted()
        }
        guard labels != measurements.searchLabels else { return measurements }
        return PipelineInputMeasurements(areas: measurements.areas, areaLabels: measurements.areaLabels,
            walkFromBase: measurements.walkFromBase, areaWalkMinutes: measurements.areaWalkMinutes,
            alwaysOpenPlaceIDs: measurements.alwaysOpenPlaceIDs, arrivalWalkMinutes: measurements.arrivalWalkMinutes,
            departureWalkMinutes: measurements.departureWalkMinutes,
            arrivalMarginMinutes: measurements.arrivalMarginMinutes,
            departureMarginMinutes: measurements.departureMarginMinutes, searchLabels: labels)
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
        let labelled = Self.withInterestLabels(measurements, verified)
        let additions = verified.places.filter { facts.places[$0.id] == nil }
        guard !additions.isEmpty else { return (facts, labelled) }
        let start = ContinuousClock.now
        var places = facts.places
        var sources = facts.sources
        for place in additions { places[place.id] = place }
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: Date())
        guard let year = components.year, let month = components.month, let day = components.day,
              let today = LocalDate(year: year, month: month, day: day) else { throw SourcePreparationError.service }
        // OpenStreetMap places already carry their opening hours, so only the Foursquare places are looked up.
        let foursquareAdditions = additions.filter { !$0.id.hasPrefix(OverpassPlacesSource.idPrefix) }
        let lookup = await OverpassHoursSource(fetcher: fetcher).hours(for: foursquareAdditions.map {
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
        for place in additions where place.id.hasPrefix(OverpassPlacesSource.idPrefix)
            && (place.hours.hoursKnown || !place.facts.isEmpty) {
            guard let source = OverpassPlacesSource.source(forPlaceId: place.id, checkedAt: today),
                  !sources.contains(where: { $0.id == source.id }) else { continue }
            sources.append(source)
        }
        let hasFoursquarePlace = additions.contains { $0.id.hasPrefix("fsq:") }
        if hasFoursquarePlace && !sources.contains(where: { $0.id == FoursquarePlacesSource.sourceId }) {
            sources.append(Source(id: FoursquarePlacesSource.sourceId, url: "https://foursquare.com",
                                  title: "Foursquare", checkedAt: today))
        }
        let newFacts = TripFacts(trip: facts.trip, bookings: facts.bookings, stay: facts.stay, places: places,
                                 practical: facts.practical, sources: sources)
        let (updated, walks) = try await SourcePreparation.measure(newFacts, geocoder: geocoder,
                                                                   searchLabels: labelled.searchLabels)
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
