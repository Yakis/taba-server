import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

public actor SuggestionPreparation {
    private let fetcher: CappedFetcher
    private let initial: TripFacts
    private let record: SourceRecord
    private let geocoder: NominatimGeocoder
    private let openStreetMap: OpenStreetMapPlaces
    /// How many suggested places are looked up for one trip. Each is one or two Nominatim lookups, or an Overpass
    /// lookup when Nominatim fails.
    public static let maximumSuggestions = 20
    private var count = 0

    public init(fetcher: CappedFetcher, facts: TripFacts, record: SourceRecord,
                geocoder: NominatimGeocoder? = nil) {
        self.init(fetcher: fetcher, facts: facts, record: record, geocoder: geocoder,
                  openStreetMap: OpenStreetMapPlaces(fetcher: fetcher))
    }

    init(fetcher: CappedFetcher, facts: TripFacts, record: SourceRecord,
         geocoder: NominatimGeocoder?, openStreetMap: OpenStreetMapPlaces) {
        self.fetcher = fetcher
        self.initial = facts
        self.record = record
        self.geocoder = geocoder ?? NominatimGeocoder(fetcher: fetcher)
        self.openStreetMap = openStreetMap
    }

    public func resolve(_ suggestion: SuggestedPlace) async throws -> Place? {
        guard count < Self.maximumSuggestions else { return nil }
        count += 1
        if let existing = existingCandidate(for: suggestion) {
            await record.append(["event": .string("suggestion"), "result": .string("existing"),
                                 "placeID": .string(existing.id)])
            return existing
        }
        return try await resolveByName(suggestion, centre: initial.trip.destination.centre)
    }

    /// The candidate already in the trip that has the suggested kind and the most similar name, when that similarity is
    /// acceptable. Ties go to the smaller id. No request is sent.
    private func existingCandidate(for suggestion: SuggestedPlace) -> Place? {
        let city = initial.trip.destination.name
        let similar = initial.places.values.compactMap { place -> (place: Place, similarity: Double)? in
            guard place.kind == suggestion.kind else { return nil }
            let similarity = NameTokens.nameSimilarity(suggestion.name, place.name, cityName: city)
            guard similarity >= NameTokens.acceptableSimilarity else { return nil }
            return (place, similarity)
        }
        return similar.min { first, second in
            if first.similarity != second.similarity { return first.similarity > second.similarity }
            return first.place.id < second.place.id
        }?.place
    }

    /// The OpenStreetMap lookup for a suggestion, matched by name within 10 km. Nominatim is asked first, as it is fast
    /// and reliable for names. Overpass is asked only when Nominatim fails; a Nominatim answer with no match is final.
    private func resolveByName(_ suggestion: SuggestedPlace, centre: Coordinate) async throws -> Place? {
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

    /// Research says what a suggested place is. A place source often files a street or a hill under another kind
    /// ("other", "landmark"), and indoor follows the kind, so the place could be taken for indoors. A suggested street,
    /// neighbourhood or viewpoint keeps its own kind and is outdoors when the source gave it "other" or "landmark".
    /// Every other place comes back as it is.
    static func keepingSuggestedKind(_ place: Place, suggested: PlaceKind) -> Place {
        let outdoorKinds: Set<PlaceKind> = [.street, .neighbourhood, .viewpoint]
        guard outdoorKinds.contains(suggested), [PlaceKind.other, .landmark].contains(place.kind) else { return place }
        return Place(id: place.id, name: place.name, kind: suggested, location: place.location, hours: place.hours,
                     priceLevel: place.priceLevel, booking: place.booking, indoor: false, images: place.images,
                     facts: place.facts, copy: place.copy, website: place.website, phone: place.phone)
    }

    /// The measured search labels with research's labels added to each verified suggested place:
    /// `InterestMatch.researchLabel` for every such place, and "interest:<interest>" for each interest the
    /// suggestion names (see `InterestMatch.interestLabel`). Labels the place already has are kept, with no
    /// duplicates, and sorted.
    static func withResearchLabels(_ measurements: PipelineInputMeasurements, _ verified: VerifiedResearch)
        -> PipelineInputMeasurements {
        var labels = measurements.searchLabels
        for (suggestion, place) in zip(verified.result.suggestedPlaces, verified.places) {
            let interests = (suggestion.interests ?? [])
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { InterestMatch.interestLabel(for: $0) }
            let added = [InterestMatch.researchLabel] + interests
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

    public func prepare(_ verified: VerifiedResearch, facts: TripFacts,
                        measurements: PipelineInputMeasurements) async throws
        -> (TripFacts, PipelineInputMeasurements) {
        let labelled = Self.withResearchLabels(measurements, verified)
        let additions = verified.places.filter { facts.places[$0.id] == nil }
        guard !additions.isEmpty else { return (facts, labelled) }
        let start = ContinuousClock.now
        var places = facts.places
        var sources = facts.sources
        for place in additions { places[place.id] = place }
        let components = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: Date())
        guard let year = components.year, let month = components.month, let day = components.day,
              let today = LocalDate(year: year, month: month, day: day) else { throw SourcePreparationError.service }
        // OpenStreetMap places already carry their opening hours, so only the places from elsewhere are looked up.
        let lookupAdditions = additions.filter { !$0.id.hasPrefix(OverpassPlacesSource.idPrefix) }
        let lookup = await OverpassHoursSource(fetcher: fetcher).hours(for: lookupAdditions.map {
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
