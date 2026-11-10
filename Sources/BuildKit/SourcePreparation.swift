import Foundation
import FoursquareKit
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

public struct Prepared: Sendable {
    public let facts: TripFacts
    public let measurements: PipelineInputMeasurements
    public let weather: [DayWeather]
    public let stayArea: String
}

public enum SourcePreparation {
    public static func prepare(_ options: SourceInput, fetcher: CappedFetcher, key: String,
                               record: SourceRecord) async throws -> Prepared {
        let geocoder = NominatimGeocoder(fetcher: fetcher)
        let basics = try await prepareBasics(options, fetcher: fetcher, geocoder: geocoder, record: record)
        return try await prepareCandidates(options, basics: basics, fetcher: fetcher, key: key,
                                           geocoder: geocoder, record: record)
    }

    public static func prepareBasics(_ options: SourceInput, fetcher: CappedFetcher,
                                     geocoder: NominatimGeocoder, record: SourceRecord) async throws
        -> BasicsCheckpoint {
        let seed = options.facts
        if let seed {
            guard seed.trip.dates.start == options.from, seed.trip.dates.end == options.to,
                  seed.trip.destination.name.caseInsensitiveCompare(options.destination) == .orderedSame,
                  options.stay == nil else { throw SourcePreparationError.factsMismatch }
        }
        let centre: Coordinate
        let country: String
        if let seed {
            centre = seed.trip.destination.centre
            country = seed.trip.destination.countryCode
        } else {
            guard let found = try await geocoder.geocode(options.destination), let code = found.countryCode else {
                throw SourcePreparationError.geocoding
            }
            centre = found.coordinate
            country = code
        }
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: Date())
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let today = LocalDate(year: year, month: month, day: day) else { throw SourcePreparationError.service }
        let weatherStart = ContinuousClock.now
        let outlook = try await OpenMeteoWeatherSource(fetcher: fetcher)
            .outlook(at: centre, from: options.from, to: options.to, today: today)
        await record.append(["event": .string("weather"), "seconds": .number(seconds(weatherStart.duration(to: .now)))])
        guard TimeZone(identifier: outlook.timeZoneId) != nil else { throw SourcePreparationError.service }
        let base = try await baseFacts(options, seed: seed, centre: centre, country: country,
                                       timeZone: outlook.timeZoneId, geocoder: geocoder)
        var sources = base.sources
        let practical = assumptions(options, seed: seed, country: country, today: today,
                                    luggageFound: base.stay.luggage != nil, sources: &sources)
        let facts = TripFacts(trip: base.trip, bookings: base.bookings, stay: base.stay, places: base.places,
                              practical: practical, sources: sources)
        return BasicsCheckpoint(facts: facts, weather: outlook.days, today: today)
    }

    // swiftlint:disable:next function_parameter_count
    public static func prepareCandidates(_ options: SourceInput, basics: BasicsCheckpoint, fetcher: CappedFetcher,
                                         key: String, geocoder: NominatimGeocoder, record: SourceRecord) async throws
        -> Prepared {
        let started = ContinuousClock.now
        let base = basics.facts.value
        var places = base.places
        var sources = base.sources
        let (lookup, searchLabels) = try await collectCandidates(options, fetcher: fetcher, key: key,
            today: basics.today, centre: base.trip.destination.centre, seed: options.facts, places: &places,
            sources: &sources, record: record)
        let facts = TripFacts(trip: base.trip, bookings: base.bookings, stay: base.stay, places: places,
                              practical: base.practical, sources: sources)
        let (measurements, stayWalks) = try await measure(facts, geocoder: geocoder, searchLabels: searchLabels)
        let weather = basics.weather.map(\.value)
        await recordSources(facts, measurements: measurements, walks: stayWalks, weather: weather,
                            lookup: lookup, started: started, record: record)
        return Prepared(facts: facts, measurements: measurements, weather: weather,
                        stayArea: measurements.areaLabels[base.stay.placeId] ?? options.destination)
    }

    // swiftlint:disable function_parameter_count
    /// `luggageFound` says whether the plan's stay has a luggage store. It matters only when the traveller named one.
    public static func assumptions(_ options: SourceInput, seed: Guide?, country: String, today: LocalDate,
                                   luggageFound: Bool, sources: inout [Source]) -> [Fact] {
        if let seed { return seed.practical }
        let source = Source(id: "taba-assumptions", url: "https://example.com/assumptions",
                            title: "Planning assumptions", checkedAt: today)
        sources.append(source)
        let accommodation = options.stay == nil
            ? "Accommodation is not booked; the base is an approximate destination centre. "
                + "Choose accommodation. Check-in 15:00 and check-out 11:00 are placeholders, not confirmed."
            : "Stay check-in 15:00 and check-out 11:00 are assumptions, not confirmed. Confirm both times."
        var facts = [Fact(text: accommodation, sourceId: source.id, checkedAt: today),
                     Fact(text: "Budget currency \(currency(for: country)) is assumed; confirm it.",
                          sourceId: source.id, checkedAt: today)]
        // Hand luggage only means there are no bags to store, so there is no luggage store to report on.
        if options.luggage != nil && !options.handLuggageOnly {
            let luggage = luggageFound
                ? "Luggage store hours 08:00 to 20:00 are an assumption, not confirmed. "
                    + "Check them before relying on it."
                : "The luggage store could not be found on the map, so the plan carries the bags. "
                    + "Check where bags can be left."
            facts.append(Fact(text: luggage, sourceId: source.id, checkedAt: today))
        }
        return facts
    }
    // swiftlint:enable function_parameter_count

    // swiftlint:disable:next function_parameter_count
    static func recordSources(_ facts: TripFacts, measurements: PipelineInputMeasurements, walks: [String: Int],
                              weather: [DayWeather], lookup: OverpassLookup, started: ContinuousClock.Instant,
                              record: SourceRecord) async {
        await record.append(["event": .string("sources"), "trip": value(facts.trip), "places": value(facts.places),
                             "bookings": value(facts.bookings), "stay": value(facts.stay),
                             "sources": value(facts.sources), "weather": .array(weather.map { day in .object([
                                "date": value(day.date), "rainChance": value(day.rainChance),
                                "tempMin": value(day.tempMin), "tempMax": value(day.tempMax),
                                "summary": .string(day.summary), "forecast": .bool(day.isForecast)
                             ]) }), "stayWalks": value(walks),
                             "areas": value(measurements.areas), "areaLabels": value(measurements.areaLabels),
                             "searchLabels": value(measurements.searchLabels),
                             "areaWalks": measurements.areaWalkMinutes,
                             "arrivalWalkMinutes": .integer(measurements.arrivalWalkMinutes),
                             "departureWalkMinutes": .integer(measurements.departureWalkMinutes),
                             "arrivalMarginMinutes": .integer(measurements.arrivalMarginMinutes),
                             "departureMarginMinutes": .integer(measurements.departureMarginMinutes),
                             "overpassUnavailable": .bool(lookup.error != nil),
                             "seconds": .number(seconds(started.duration(to: .now)))])
    }

    /// The interest search labels that found each place, by place id. Only the labels of `interestSearches` count.
    static func searchLabels(_ report: FoursquarePlacesSource.SweepReport,
                             interestSearches: [FoursquarePlacesSource.CategorySearch]) -> [String: [String]] {
        let interestLabels = Set(interestSearches.map(\.label))
        var labels: [String: Set<String>] = [:]
        for sweep in report.sweeps where interestLabels.contains(sweep.label) {
            for id in sweep.placeIds { labels[id, default: []].insert(sweep.label) }
        }
        return labels.mapValues { $0.sorted() }
    }

    // swiftlint:disable:next function_parameter_count
    static func collectCandidates(_ options: SourceInput, fetcher: CappedFetcher, key: String, today: LocalDate,
                                  centre: Coordinate, seed: Guide?, places: inout [String: Place],
                                  sources: inout [Source],
                                  record: SourceRecord) async throws -> (OverpassLookup, [String: [String]]) {
        let started = ContinuousClock.now
        let baseKinds: [PlaceKind] = [.cafe, .restaurant, .pub, .viewpoint, .museum, .market, .shop, .grocery]
        let interestSearches = InterestSearches.searches(for: options.preferences.interests)
        let searches = FoursquarePlacesSource.searches(for: baseKinds) + interestSearches
        let report = await FoursquarePlacesSource(fetcher: fetcher, apiKey: key)
            .sweep(searches: searches, around: centre, limit: 6, checkedAt: today)
        try Task.checkCancellation()
        await record.append(["event": .string("foursquareSweep"),
                             "seconds": .number(seconds(started.duration(to: .now))),
                             "outcomes": .array(report.sweeps.map {
            .object(["kind": .string($0.label), "returned": .integer($0.returned),
                     "failureCategory": .string($0.failure == nil ? "none" : "sourceFailure")])
        })])
        let additions = report.places.filter { places[$0.id] == nil }
        for place in additions { places[place.id] = place }
        guard !report.places.isEmpty || seed != nil else { throw SourcePreparationError.noCandidates }
        if !report.places.isEmpty && !sources.contains(where: { $0.id == FoursquarePlacesSource.sourceId }) {
            sources.append(Source(id: FoursquarePlacesSource.sourceId, url: "https://foursquare.com",
                                  title: "Foursquare", checkedAt: today))
        }
        let lookup = try await addHours(additions, city: options.destination, today: today, fetcher: fetcher,
                                        places: &places, sources: &sources, record: record)
        return (lookup, searchLabels(report, interestSearches: interestSearches))
    }

    // swiftlint:disable:next function_parameter_count
    static func addHours(_ additions: [Place], city: String, today: LocalDate, fetcher: CappedFetcher,
                         places: inout [String: Place], sources: inout [Source],
                         record: SourceRecord) async throws -> OverpassLookup {
        let started = ContinuousClock.now
        let targets = additions.map { HoursLookupTarget(placeId: $0.id, name: $0.name,
                                                        coordinate: $0.location.coordinate) }
        let lookup = await OverpassHoursSource(fetcher: fetcher).hours(for: targets, cityName: city, checkedAt: today)
        try Task.checkCancellation()
        await record.append(overpassEvent(lookup, seconds: seconds(started.duration(to: .now))))
        for result in lookup.results {
            guard case .found(let found) = result.outcome, let old = places[result.placeId] else { continue }
            places[old.id] = Place(id: old.id, name: old.name, kind: old.kind, location: old.location,
                                   hours: found.reading.hours, priceLevel: old.priceLevel, booking: old.booking,
                                   indoor: old.indoor, images: old.images, facts: old.facts, copy: old.copy)
            if !sources.contains(where: { $0.id == found.source.id }) { sources.append(found.source) }
        }
        return lookup
    }

    /// The evidence event for one Overpass lookup. `error` is recorded only when a batch failed, as its text.
    static func overpassEvent(_ lookup: OverpassLookup, seconds: Double) -> [String: JSONValue] {
        let unavailable = lookup.results.filter { if case .unavailable = $0.outcome { true } else { false } }.count
        let foundHours = lookup.results.filter { if case .found = $0.outcome { true } else { false } }.count
        var event: [String: JSONValue] = ["event": .string("overpass"), "found": .integer(foundHours),
                                          "unavailable": .integer(unavailable), "seconds": .number(seconds)]
        if let error = lookup.error {
            event["error"] = .string(String(describing: error))
        }
        return event
    }

    // swiftlint:disable:next function_parameter_count
    public static func baseFacts(_ options: SourceInput, seed: Guide?, centre: Coordinate, country: String,
                                 timeZone: String, geocoder: NominatimGeocoder) async throws -> TripFacts {
        if let seed {
            guard seed.trip.destination.timeZoneId == timeZone else { throw SourcePreparationError.factsMismatch }
            return TripFacts(trip: seed.trip, bookings: seed.bookings, stay: seed.stay, places: seed.places,
                             practical: seed.practical, sources: seed.sources)
        }
        let found: GeocodedPlace?
        if let name = options.stay {
            found = try await geocoder.geocode(name + ", " + options.destination)
            if found == nil { throw SourcePreparationError.geocoding }
        } else { found = nil }
        guard let checkIn = LocalTime("15:00"), let checkOut = LocalTime("11:00") else {
            throw SourcePreparationError.service
        }
        let place = Place(id: "manual:stay", name: options.stay ?? "Unbooked base (choose accommodation)",
                          kind: .lodging, location: PlaceLocation(coordinate: found?.coordinate ?? centre,
                          address: found?.displayName, approximate: options.stay == nil),
                          hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: []), priceLevel: nil,
                          booking: PlaceBooking(needed: false, url: nil), indoor: true,
                          images: [], facts: [], copy: nil)
        // With hand luggage only, no luggage store is looked up at all.
        let store: (place: Place, slot: LuggageSlot)?
        if options.handLuggageOnly {
            store = nil
        } else {
            store = try await luggageStore(options, geocoder: geocoder)
        }
        var places = [place.id: place]
        if let store { places[store.place.id] = store.place }
        let stay = Stay(placeId: place.id, checkIn: checkIn, checkOut: checkOut, luggage: store?.slot,
                        handLuggageOnly: options.handLuggageOnly ? true : nil)
        let trip = Trip(destination: Destination(name: options.destination, countryCode: country,
                                                 timeZoneId: timeZone, centre: centre),
                        dates: TripDates(start: options.from, end: options.to, arrives: options.arrives,
                                         leaves: options.leaves),
                        party: options.preferences.party,
                        budget: Budget(currencyCode: currency(for: country), stayMaxPerNight: 0,
                                       dailySpend: options.preferences.dailySpend),
                        interests: options.preferences.interests, pace: options.preferences.pace,
                        voice: "Warm, practical and concise")
        return TripFacts(trip: trip, bookings: [], stay: stay, places: places, practical: [], sources: [])
    }

    public static func measure(_ facts: TripFacts, geocoder: NominatimGeocoder,
                               searchLabels: [String: [String]] = [:]) async throws
        -> (PipelineInputMeasurements, [String: Int]) {
        let places = facts.places
        guard let stayPlace = places[facts.stay.placeId] else { throw SourcePreparationError.factsMismatch }
        let candidates = places.values.map { AreaCandidate(id: $0.id, coordinate: $0.location.coordinate) }
        let areas = try await AreaNameFallback.cluster(candidates, destination: facts.trip.destination.name) { point in
            try await geocoder.areaName(near: point, preferSuburbOrQuarter: true)
        }
        let walker = StraightLineWalkTimes()
        let walks = places.mapValues { walker.minutes(from: stayPlace.location.coordinate, to: $0.location.coordinate) }
        let arrivals = facts.bookings.filter { $0.arrives.date == facts.trip.dates.start }
            .compactMap { $0.toPlaceId.flatMap { places[$0] } }
        let departures = facts.bookings.filter { $0.departs.date == facts.trip.dates.end }
            .compactMap { $0.fromPlaceId.flatMap { places[$0] } }
        func maximum(_ anchors: [Place]) -> Int {
            anchors.flatMap { anchor in places.values.map {
                walker.minutes(from: anchor.location.coordinate, to: $0.location.coordinate)
            } }.max() ?? 0
        }
        return (PipelineInputMeasurements(areas: areas, places: places, stayWalks: walks,
                    arrivalWalkMinutes: maximum(arrivals), departureWalkMinutes: maximum(departures),
                    searchLabels: searchLabels), walks)
    }

    public static func currency(for country: String) -> String {
        switch country.uppercased() {
        case "GB": "GBP"
        case "US": "USD"
        case "AT", "BE", "HR", "CY", "EE", "FI", "FR", "DE", "GR", "IE", "IT", "LV", "LT", "LU",
             "MT", "NL", "PT", "SK", "SI", "ES": "EUR"
        default: "XXX"
        }
    }
}

func seconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}
