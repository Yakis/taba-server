import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoursquareKit
import GuideKit
import SourcesKit

// One run for a person to read. It makes at most 30 requests, and it never prints the Foursquare key.
// The key is read from FOURSQUARE_API_KEY. Without it, the Foursquare sweep and the hours lookup are skipped.
// Each source runs on its own. A failure is printed and the run carries on with the next source.

let requestLimit = 30
let destinationName = "Edinburgh"
let timeZoneId = "Europe/London"
let placesToReverseGeocode = 3
let weatherDaysAhead = 2

/// Today's date at the destination, from the destination's time zone.
func localToday() -> LocalDate? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneId) ?? .current
    let parts = calendar.dateComponents([.year, .month, .day], from: Date())
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return LocalDate(year: year, month: month, day: day)
}

/// Seconds to one decimal place, for the elapsed-time lines.
func seconds(_ duration: Duration) -> String {
    let parts = duration.components
    let total = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    return String(format: "%.1f s", total)
}

/// Runs one source and prints its elapsed time. A failure is printed, and nil is returned, so the caller moves on.
func step<Value>(_ name: String, _ work: () async throws -> Value) async -> Value? {
    let clock = ContinuousClock()
    let started = clock.now
    do {
        let value = try await work()
        print("\(name): finished in \(seconds(started.duration(to: clock.now))).")
        return value
    } catch {
        print("\(name): failed after \(seconds(started.duration(to: clock.now))): \(error)")
        return nil
    }
}

/// Foursquare cafes and pubs around the centre. Empty, with a message, when the key is not set.
func foursquarePlaces(fetcher: CappedFetcher, centre: GeocodedPlace, today: LocalDate) async -> [Place] {
    guard let key = ProcessInfo.processInfo.environment["FOURSQUARE_API_KEY"], !key.isEmpty else {
        print("FOURSQUARE_API_KEY is not set, so the Foursquare sweep is skipped.")
        return []
    }
    let source = FoursquarePlacesSource(fetcher: fetcher, apiKey: key)
    let report = await source.sweep(kinds: [.cafe, .pub], around: centre.coordinate, limit: 10, checkedAt: today)
    for sweep in report.sweeps {
        let note = sweep.failure.map { " (failed: \($0))" } ?? ""
        print("Foursquare \(sweep.kind.rawValue): \(sweep.returned) returned\(note).")
    }
    print("Foursquare places after de-duplication and closed filtering: \(report.places.count).")
    return report.places
}

/// Summarises the OSM lookup. Places whose batch failed are unknown, not "not found".
func reportOSMHours(_ lookup: OverpassLookup) {
    var readable = 0
    var unreadable = 0
    var notFound = 0
    var unavailable = 0
    var warnings: [String: Int] = [:]
    for result in lookup.results {
        switch result.outcome {
        case .found(let hours):
            if hours.reading.hours.hoursKnown {
                readable += 1
            } else {
                unreadable += 1
            }
            for warning in hours.reading.warnings {
                warnings[warning, default: 0] += 1
            }
            if let reason = hours.reading.reason {
                warnings["unreadable: \(reason)", default: 0] += 1
            }
        case .notFound:
            notFound += 1
        case .unavailable:
            unavailable += 1
        }
    }
    print("OSM hours for \(lookup.results.count) places: \(readable) read, \(unreadable) found but unreadable, "
        + "\(notFound) not found, \(unavailable) unavailable.")
    if let error = lookup.error {
        print("OSM lookup reported: \(error). The hours of the unavailable places are unknown.")
    }
    printWarnings(warnings)
}

func printWarnings(_ warnings: [String: Int]) {
    guard !warnings.isEmpty else {
        print("Parser warnings: none.")
        return
    }
    print("Parser warnings:")
    for (text, count) in warnings.sorted(by: { $0.key < $1.key }) {
        print("  \(count) x \(text)")
    }
}

func reportWeather(_ outlook: WeatherOutlook) {
    print("Weather (time zone \(outlook.timeZoneId)):")
    for day in outlook.days {
        let rain = day.rainChance.map { "\($0)% rain" } ?? "no rain chance"
        let low = day.tempMin.map { String(Int($0.rounded())) } ?? "?"
        let high = day.tempMax.map { String(Int($0.rounded())) } ?? "?"
        let kind = day.isForecast ? "forecast" : "typical"
        print("  \(day.date) \(kind): \(day.summary), \(low)-\(high) C, \(rain).")
    }
}

func run() async {
    guard let today = localToday() else {
        print("Could not work out today's date, so nothing was run.")
        return
    }
    let fetcher = CappedFetcher(inner: URLSessionFetcher(), limit: requestLimit)
    let geocoder = NominatimGeocoder(fetcher: fetcher)

    let found = await step("Geocoding") { try await geocoder.geocode(destinationName) }
    guard let centre = found ?? nil else {
        print("No centre for \(destinationName), so the sources that need one are skipped.")
        print("Requests made: \(await fetcher.sentCount) of \(requestLimit).")
        return
    }
    print("Centre: \(centre.displayName) (\(centre.countryCode ?? "no country code")).")

    let places = await step("Foursquare sweep") {
        await foursquarePlaces(fetcher: fetcher, centre: centre, today: today)
    } ?? []

    if !places.isEmpty {
        let targets = places.map { place in
            HoursLookupTarget(placeId: place.id, name: place.name, coordinate: place.location.coordinate)
        }
        let overpass = OverpassHoursSource(fetcher: fetcher)
        let lookup = await step("OSM hours") {
            await overpass.hours(for: targets, cityName: destinationName, checkedAt: today)
        }
        if let lookup {
            reportOSMHours(lookup)
        }
    }

    if let weatherEnd = today.adding(days: weatherDaysAhead) {
        let weather = OpenMeteoWeatherSource(fetcher: fetcher)
        let outlook = await step("Weather") {
            try await weather.outlook(at: centre.coordinate, from: today, to: weatherEnd, today: today)
        }
        if let outlook {
            reportWeather(outlook)
        }
    }

    _ = await step("Area names") {
        for place in places.prefix(placesToReverseGeocode) {
            do {
                let area = try await geocoder.areaName(near: place.location.coordinate)
                print("Area for \(place.name): \(area ?? "none found").")
            } catch {
                print("Area for \(place.name) failed: \(error)")
            }
        }
    }

    print("Requests made: \(await fetcher.sentCount) of \(requestLimit).")
}

await run()
