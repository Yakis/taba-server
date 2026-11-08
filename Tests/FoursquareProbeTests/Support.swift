import Foundation
import FoursquareKit
import GuideKit

/// Test helpers. Foursquare JSON is written by hand from the documented shape, never copied from a live response.
enum Samples {
    static func decodePlaces(_ json: String) throws -> [FoursquarePlace] {
        try JSONDecoder().decode(FoursquareSearchResponse.self, from: Data(json.utf8)).results
    }

    static func decodePlace(_ json: String) throws -> FoursquarePlace {
        try JSONDecoder().decode(FoursquarePlace.self, from: Data(json.utf8))
    }

    static let abbotsfordJSON = """
    {"fsq_place_id":"4b5f2d1e0000000000000001","name":"The Abbotsford",
     "latitude":55.9532705,"longitude":-3.1946516,
     "location":{"address":"3-5 Rose Street","formatted_address":"3-5 Rose Street, Edinburgh EH2 2PR",
                 "locality":"Edinburgh","postcode":"EH2 2PR","country":"GB"},
     "categories":[{"fsq_category_id":"4bf58dd8d48988d11b941735","name":"Pubs"}],
     "date_closed":""}
    """

    static let detailsJSON = """
    {"fsq_place_id":"4b5f2d1e0000000000000001","name":"The Abbotsford",
     "latitude":55.9532705,"longitude":-3.1946516,
     "location":{"address":"3-5 Rose Street","formatted_address":"3-5 Rose Street, Edinburgh EH2 2PR"},
     "categories":[{"fsq_category_id":"4bf58dd8d48988d11b941735","name":"Pubs"}],
     "hours":{"display":"Open until 1:00 AM","open_now":true,
              "regular":[{"day":1,"open":"1100","close":"0100"},
                         {"day":7,"open":"1200","close":"2400"},
                         {"day":3,"open":"1000","close":"2200"},
                         {"day":9,"open":"1000","close":"2200"}]},
     "rating":8.1}
    """

    static func place(_ id: String, name: String, kind: PlaceKind, hours: OpeningHours) -> Place {
        Place(
            id: id,
            name: name,
            kind: kind,
            location: PlaceLocation(coordinate: coordinate(55.9533, -3.1883), address: nil, approximate: false),
            hours: hours,
            priceLevel: nil,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: true,
            images: [],
            facts: [],
            copy: nil
        )
    }

    static func coordinate(_ latitude: Double, _ longitude: Double) -> Coordinate {
        guard let value = Coordinate(latitude: latitude, longitude: longitude) else {
            preconditionFailure("bad test coordinate")
        }
        return value
    }

    static func date(_ text: String) -> LocalDate {
        guard let value = LocalDate(text) else { preconditionFailure("bad test date") }
        return value
    }

    /// A small guide with the given places, for the plan tests.
    static func guide(places: [Place]) -> Guide {
        let destination = Destination(
            name: "Testville",
            countryCode: "GB",
            timeZoneId: "Europe/London",
            centre: coordinate(55.9533, -3.1883)
        )
        let trip = Trip(
            destination: destination,
            dates: TripDates(start: date("2026-11-22"), end: date("2026-11-24")),
            party: Party(adults: 1, children: 0, mobilityNotes: []),
            budget: Budget(currencyCode: "GBP", stayMaxPerNight: 100, dailySpend: .low),
            interests: [],
            pace: .relaxed,
            voice: "Plain."
        )
        let stay = Stay(
            placeId: "manual:stay",
            checkIn: LocalTime("15:00") ?? LocalTime(minutesSinceMidnight: 900) ?? LocalTime.midnightFallback,
            checkOut: LocalTime("11:00") ?? LocalTime(minutesSinceMidnight: 660) ?? LocalTime.midnightFallback,
            luggage: nil
        )
        var dictionary: [String: Place] = [:]
        for place in places {
            dictionary[place.id] = place
        }
        return Guide(
            id: "test",
            version: 1,
            status: .draft,
            trip: trip,
            bookings: [],
            stay: stay,
            places: dictionary,
            days: [],
            lists: [],
            tasting: [],
            practical: [],
            sources: []
        )
    }
}

extension LocalTime {
    /// Only used to avoid force unwraps in test helpers. Midnight is always valid.
    static var midnightFallback: LocalTime {
        guard let midnight = LocalTime(minutesSinceMidnight: 0) else { preconditionFailure("midnight") }
        return midnight
    }
}
