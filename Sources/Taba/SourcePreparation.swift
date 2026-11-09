import Foundation
import FoursquareKit
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

struct Prepared: Sendable {
    let facts: TripFacts
    let measurements: PipelineInputMeasurements
    let weather: [DayWeather]
    let stayArea: String
}

enum SourcePreparation {
    static func prepare(_ options: Options, fetcher: CappedFetcher, key: String,
                        record: RunRecord) async throws -> Prepared {
        let started = ContinuousClock.now
        let geocoder = NominatimGeocoder(fetcher: fetcher)
        print("Preparing sources...")
        let seed: Guide?
        if let path = options.facts {
            let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            guard guide.trip.dates.start == options.from, guide.trip.dates.end == options.to,
                  guide.trip.destination.name.caseInsensitiveCompare(options.destination) == .orderedSame,
                  options.stay == nil else { throw CLIError.factsMismatch }
            seed = guide
        } else { seed = nil }
        let centre: Coordinate
        let country: String
        if let seed {
            centre = seed.trip.destination.centre
            country = seed.trip.destination.countryCode
        } else {
            guard let found = try await geocoder.geocode(options.destination), let code = found.countryCode else {
                throw CLIError.geocoding
            }
            centre = found.coordinate
            country = code
        }
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: Date())
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let today = LocalDate(year: year, month: month, day: day) else { throw CLIError.service }
        let weatherStart = ContinuousClock.now
        let outlook = try await OpenMeteoWeatherSource(fetcher: fetcher)
            .outlook(at: centre, from: options.from, to: options.to, today: today)
        await record.append(["event": .string("weather"), "seconds": .number(seconds(weatherStart.duration(to: .now)))])
        guard TimeZone(identifier: outlook.timeZoneId) != nil else { throw CLIError.service }
        let base = try await baseFacts(options, seed: seed, centre: centre, country: country,
                                       timeZone: outlook.timeZoneId, geocoder: geocoder)
        let trip = base.trip
        let stay = base.stay
        var places = base.places
        var sources = base.sources
        let lookup = try await collectCandidates(options, fetcher: fetcher, key: key, today: today,
                                                 centre: centre, seed: seed, places: &places,
                                                 sources: &sources, record: record)
        let practical = assumptions(options, seed: seed, country: country, today: today, sources: &sources)
        let facts = TripFacts(trip: trip, bookings: seed?.bookings ?? [], stay: stay, places: places,
                              practical: practical, sources: sources)
        let (measurements, stayWalks) = try await measure(facts, geocoder: geocoder)
        await recordSources(facts, measurements: measurements, walks: stayWalks, weather: outlook.days,
                            lookup: lookup, started: started, record: record)
        try await record.check()
        return Prepared(facts: facts, measurements: measurements, weather: outlook.days,
                        stayArea: measurements.areaLabels[stay.placeId] ?? options.destination)
    }

    static func assumptions(_ options: Options, seed: Guide?, country: String, today: LocalDate,
                            sources: inout [Source]) -> [Fact] {
        if let seed { return seed.practical }
        let source = Source(id: "taba-assumptions", url: "https://example.com/assumptions",
                            title: "Planning assumptions", checkedAt: today)
        sources.append(source)
        let accommodation = options.stay == nil
            ? "Accommodation is not booked; the base is an approximate destination centre. "
                + "Choose accommodation. Check-in 15:00 and check-out 11:00 are placeholders, not confirmed."
            : "Stay check-in 15:00 and check-out 11:00 are assumptions, not confirmed. Confirm both times."
        return [Fact(text: accommodation, sourceId: source.id, checkedAt: today),
                Fact(text: "Budget currency \(currency(for: country)) is assumed; confirm it.",
                     sourceId: source.id, checkedAt: today)]
    }

    // swiftlint:disable:next function_parameter_count
    static func recordSources(_ facts: TripFacts, measurements: PipelineInputMeasurements, walks: [String: Int],
                              weather: [DayWeather], lookup: OverpassLookup, started: ContinuousClock.Instant,
                              record: RunRecord) async {
        await record.append(["event": .string("sources"), "trip": value(facts.trip), "places": value(facts.places),
                             "bookings": value(facts.bookings), "stay": value(facts.stay),
                             "sources": value(facts.sources), "weather": .array(weather.map { day in .object([
                                "date": value(day.date), "rainChance": value(day.rainChance),
                                "tempMin": value(day.tempMin), "tempMax": value(day.tempMax),
                                "summary": .string(day.summary), "forecast": .bool(day.isForecast)
                             ]) }), "stayWalks": value(walks),
                             "areas": value(measurements.areas), "areaLabels": value(measurements.areaLabels),
                             "areaWalks": measurements.areaWalkMinutes,
                             "arrivalWalkMinutes": .integer(measurements.arrivalWalkMinutes),
                             "departureWalkMinutes": .integer(measurements.departureWalkMinutes),
                             "arrivalMarginMinutes": .integer(measurements.arrivalMarginMinutes),
                             "departureMarginMinutes": .integer(measurements.departureMarginMinutes),
                             "overpassUnavailable": .bool(lookup.error != nil),
                             "seconds": .number(seconds(started.duration(to: .now)))])
    }

    // swiftlint:disable:next function_parameter_count
    static func collectCandidates(_ options: Options, fetcher: CappedFetcher, key: String, today: LocalDate,
                                  centre: Coordinate, seed: Guide?, places: inout [String: Place],
                                  sources: inout [Source],
                                  record: RunRecord) async throws -> OverpassLookup {
        let started = ContinuousClock.now
        let report = await FoursquarePlacesSource(fetcher: fetcher, apiKey: key)
            .sweep(kinds: [.cafe, .restaurant, .pub, .viewpoint, .museum, .market, .shop, .grocery],
                   around: centre, limit: 6, checkedAt: today)
        try Task.checkCancellation()
        await record.append(["event": .string("foursquareSweep"),
                             "seconds": .number(seconds(started.duration(to: .now))),
                             "outcomes": .array(report.sweeps.map {
            .object(["kind": .string($0.kind.rawValue), "returned": .integer($0.returned),
                     "failureCategory": .string($0.failure == nil ? "none" : "sourceFailure")])
        })])
        let additions = report.places.filter { places[$0.id] == nil }
        for place in additions { places[place.id] = place }
        guard !report.places.isEmpty || seed != nil else { throw CLIError.noCandidates }
        if !report.places.isEmpty && !sources.contains(where: { $0.id == FoursquarePlacesSource.sourceId }) {
            sources.append(Source(id: FoursquarePlacesSource.sourceId, url: "https://foursquare.com",
                                  title: "Foursquare", checkedAt: today))
        }
        return try await addHours(additions, city: options.destination, today: today, fetcher: fetcher,
                                  places: &places, sources: &sources, record: record)
    }

    // swiftlint:disable:next function_parameter_count
    static func addHours(_ additions: [Place], city: String, today: LocalDate, fetcher: CappedFetcher,
                         places: inout [String: Place], sources: inout [Source],
                         record: RunRecord) async throws -> OverpassLookup {
        let started = ContinuousClock.now
        let targets = additions.map { HoursLookupTarget(placeId: $0.id, name: $0.name,
                                                        coordinate: $0.location.coordinate) }
        let lookup = await OverpassHoursSource(fetcher: fetcher).hours(for: targets, cityName: city, checkedAt: today)
        try Task.checkCancellation()
        let unavailable = lookup.results.filter { if case .unavailable = $0.outcome { true } else { false } }.count
        let foundHours = lookup.results.filter { if case .found = $0.outcome { true } else { false } }.count
        await record.append(["event": .string("overpass"), "unavailable": .integer(unavailable),
                             "found": .integer(foundHours), "seconds": .number(seconds(started.duration(to: .now)))])
        for result in lookup.results {
            guard case .found(let found) = result.outcome, let old = places[result.placeId] else { continue }
            places[old.id] = Place(id: old.id, name: old.name, kind: old.kind, location: old.location,
                                   hours: found.reading.hours, priceLevel: old.priceLevel, booking: old.booking,
                                   indoor: old.indoor, images: old.images, facts: old.facts, copy: old.copy)
            if !sources.contains(where: { $0.id == found.source.id }) { sources.append(found.source) }
        }
        return lookup
    }

    // swiftlint:disable:next function_parameter_count
    static func baseFacts(_ options: Options, seed: Guide?, centre: Coordinate, country: String,
                          timeZone: String, geocoder: NominatimGeocoder) async throws -> TripFacts {
        if let seed {
            guard seed.trip.destination.timeZoneId == timeZone else { throw CLIError.factsMismatch }
            return TripFacts(trip: seed.trip, bookings: seed.bookings, stay: seed.stay, places: seed.places,
                             practical: seed.practical, sources: seed.sources)
        }
        let found: GeocodedPlace?
        if let name = options.stay {
            found = try await geocoder.geocode(name + ", " + options.destination)
            if found == nil { throw CLIError.geocoding }
        } else { found = nil }
        guard let checkIn = LocalTime("15:00"), let checkOut = LocalTime("11:00") else { throw CLIError.service }
        let place = Place(id: "manual:stay", name: options.stay ?? "Unbooked base (choose accommodation)",
                          kind: .lodging, location: PlaceLocation(coordinate: found?.coordinate ?? centre,
                          address: found?.displayName, approximate: options.stay == nil),
                          hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: []), priceLevel: nil,
                          booking: PlaceBooking(needed: false, url: nil), indoor: true,
                          images: [], facts: [], copy: nil)
        let stay = Stay(placeId: place.id, checkIn: checkIn, checkOut: checkOut, luggage: nil)
        let trip = Trip(destination: Destination(name: options.destination, countryCode: country,
                                                 timeZoneId: timeZone, centre: centre),
                        dates: TripDates(start: options.from, end: options.to),
                        party: Party(adults: 1, children: 0, mobilityNotes: []),
                        budget: Budget(currencyCode: currency(for: country), stayMaxPerNight: 0, dailySpend: .moderate),
                        interests: [], pace: .unhurried, voice: "Warm, practical and concise")
        return TripFacts(trip: trip, bookings: [], stay: stay, places: [place.id: place], practical: [], sources: [])
    }

    static func measure(_ facts: TripFacts, geocoder: NominatimGeocoder) async throws
        -> (PipelineInputMeasurements, [String: Int]) {
        let places = facts.places
        guard let stayPlace = places[facts.stay.placeId] else { throw CLIError.factsMismatch }
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
                    arrivalWalkMinutes: maximum(arrivals), departureWalkMinutes: maximum(departures)), walks)
    }

    static func currency(for country: String) -> String {
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
