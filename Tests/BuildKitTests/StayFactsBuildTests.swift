import BuildKit
import Foundation
import GuideKit
import PipelineKit
import SourcesKit
import Testing

/// Answers Nominatim searches from a table, so the tests never reach the network. An unmatched search finds nothing.
private actor PlaceSearchFake: HTTPFetching {
    private(set) var queries: [String] = []
    private let answers: [String: String]

    init(answers: [String: String]) { self.answers = answers }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = request.url?.absoluteString ?? ""
        queries.append(url)
        let body = answers.first { url.contains($0.key) }?.value ?? "[]"
        return HTTPResponse(status: 200, body: Data(body.utf8), headers: [:])
    }
}

/// One Nominatim answer for a place in Leeds.
private func found(_ name: String, latitude: String, longitude: String) -> String {
    "[{\"lat\":\"\(latitude)\",\"lon\":\"\(longitude)\",\"display_name\":\"\(name), Leeds\","
        + "\"address\":{\"country_code\":\"gb\"}}]"
}

private let leedsCentre = (latitude: 53.7997, longitude: -1.5492)

private func options(from: String = "2026-11-14", to: String = "2026-11-14", stay: String? = nil,
                     travel: TravelMode? = nil, travelPlace: String? = nil) throws -> SourceInput {
    SourceInput(destination: "Leeds", from: try #require(LocalDate(from)), to: try #require(LocalDate(to)),
                stay: stay, travelMode: travel, travelPlace: travelPlace)
}

private func baseFacts(_ options: SourceInput, fetcher: PlaceSearchFake) async throws -> TripFacts {
    let centre = try #require(Coordinate(latitude: leedsCentre.latitude, longitude: leedsCentre.longitude))
    return try await SourcePreparation.baseFacts(options, seed: nil, centre: centre, country: "GB",
        timeZone: "Europe/London", geocoder: NominatimGeocoder(fetcher: fetcher, interval: .zero))
}

/// The practical facts the build adds for these options and the facts it made.
private func assumptionTexts(_ options: SourceInput, facts: TripFacts) throws -> [String] {
    var sources: [Source] = []
    return SourcePreparation.assumptions(options, seed: nil, today: try #require(LocalDate("2026-11-13")),
                                         facts: facts, sources: &sources).map(\.text)
}

private let station = found("Leeds Station", latitude: "53.7947", longitude: "-1.5473")

// MARK: The Leeds day trip, the observed failure

@Test func leedsDayTripByTrainHasNoStayAndStartsAtTheStation() async throws {
    let fetcher = PlaceSearchFake(answers: ["railway": station])
    let facts = try await baseFacts(try options(travel: .train), fetcher: fetcher)
    #expect(facts.places.values.allSatisfy { $0.kind != .lodging })
    #expect(facts.places["manual:stay"] == nil)
    #expect(facts.stay.placeId == nil)
    #expect(facts.stay.checkIn == nil && facts.stay.checkOut == nil && facts.stay.timesEstimated == nil)
    #expect(facts.stay.arrangement == .notNeeded)
    let hub = try #require(facts.places["manual:arrival"])
    #expect(hub.name == "Leeds station")
    #expect(hub.kind == .station)
    #expect(hub.hours.hoursKnown == false)
    #expect(hub.location.approximate == false)
    #expect(facts.trip.travel == TripTravel(mode: .train, arrivalPlaceId: "manual:arrival",
                                            departurePlaceId: "manual:arrival"))
    #expect(facts.base?.place.id == "manual:arrival")
    #expect(facts.base?.kind == .arrival(.train))
    #expect(await fetcher.queries.contains { $0.contains("Leeds") && $0.contains("railway") && $0.contains("station") })
}

@Test func leedsPracticalFactsNameTheStationAndNothingAboutSleeping() async throws {
    let fetcher = PlaceSearchFake(answers: ["railway": station])
    let options = try options(travel: .train)
    let facts = try await baseFacts(options, fetcher: fetcher)
    let texts = try assumptionTexts(options, facts: facts)
    #expect(texts == ["The day starts and ends at Leeds station, the main station on the map. "
        + "If you arrive somewhere else, the first and last walks will be different."])
    for text in texts {
        for banned in ["accommodation", "check-in", "check-out", "currency", "hotel", "budget"] {
            #expect(!text.localizedCaseInsensitiveContains(banned))
        }
    }
}

@Test func typedHubNotFoundIsReportedWithoutFailingTheBuild() async throws {
    let fetcher = PlaceSearchFake(answers: [:])
    let options = try options(travel: .train, travelPlace: "Nowhere Station")
    let facts = try await baseFacts(options, fetcher: fetcher)
    #expect(facts.places["manual:arrival"] == nil)
    #expect(facts.trip.travel == TripTravel(mode: .train, arrivalPlaceId: nil, departurePlaceId: nil))
    #expect(try assumptionTexts(options, facts: facts) == [
        "Nowhere Station could not be found on the map, so the walks to and from it are not measured."
    ])
}

@Test func typedHubFoundIsPlacedAsTypedAndAddsNoFact() async throws {
    let fetcher = PlaceSearchFake(answers: ["Bus": found("Leeds Bus Station", latitude: "53.7955",
                                                          longitude: "-1.5440")])
    let options = try options(travel: .coach, travelPlace: "Leeds Bus Station")
    let facts = try await baseFacts(options, fetcher: fetcher)
    let hub = try #require(facts.places["manual:arrival"])
    #expect(hub.name == "Leeds Bus Station")
    #expect(hub.kind == .station)
    #expect(await fetcher.queries.contains { $0.contains("Bus") && $0.contains("Leeds") })
    #expect(try assumptionTexts(options, facts: facts).isEmpty)
}

@Test func coachAndFlightWithNoPlaceLookUpTheirMainHub() async throws {
    let cases = [
        HubCase(mode: .coach, keyword: "coach", name: "Leeds coach station"),
        HubCase(mode: .flight, keyword: "airport", name: "Leeds airport")
    ]
    for item in cases {
        let fetcher = PlaceSearchFake(answers: [item.keyword: found(item.name, latitude: "53.8", longitude: "-1.6")])
        let facts = try await baseFacts(try options(travel: item.mode), fetcher: fetcher)
        #expect(facts.places["manual:arrival"]?.name == item.name)
        #expect(facts.places["manual:arrival"]?.kind == .station)
        #expect(facts.trip.travel?.arrivalPlaceId == "manual:arrival")
        #expect(facts.trip.travel?.departurePlaceId == "manual:arrival")
        #expect(await fetcher.queries.contains { $0.contains(item.keyword) && $0.contains("Leeds") })
        #expect(try assumptionTexts(try options(travel: item.mode), facts: facts).contains {
            $0.hasPrefix("The day starts and ends at \(item.name), the main")
        })
    }
}

@Test func lookedUpHubNotFoundGivesNoPlaceAndNoFact() async throws {
    let fetcher = PlaceSearchFake(answers: [:])
    let options = try options(travel: .train)
    let facts = try await baseFacts(options, fetcher: fetcher)
    #expect(facts.places["manual:arrival"] == nil)
    #expect(facts.trip.travel == TripTravel(mode: .train, arrivalPlaceId: nil, departurePlaceId: nil))
    #expect(try assumptionTexts(options, facts: facts).isEmpty)
}

@Test func carWithNoPlaceLooksUpNoHub() async throws {
    let fetcher = PlaceSearchFake(answers: [:])
    let facts = try await baseFacts(try options(travel: .car), fetcher: fetcher)
    #expect(await fetcher.queries.isEmpty)
    #expect(facts.trip.travel == TripTravel(mode: .car, arrivalPlaceId: nil, departurePlaceId: nil))
    #expect(facts.places["manual:arrival"] == nil)
    #expect(facts.base == nil)
}

@Test func noWayOfTravelGivesNoTravelAtAll() async throws {
    let fetcher = PlaceSearchFake(answers: [:])
    let facts = try await baseFacts(try options(), fetcher: fetcher)
    #expect(facts.trip.travel == nil)
    #expect(await fetcher.queries.isEmpty)
}

// MARK: Stays

@Test func overnightBookedStayHasEstimatedTimesAndItsOwnBase() async throws {
    let fetcher = PlaceSearchFake(answers: ["Hotel": found("Example Hotel", latitude: "53.7950",
                                                           longitude: "-1.5500")])
    let options = try options(to: "2026-11-15", stay: "Example Hotel")
    let facts = try await baseFacts(options, fetcher: fetcher)
    #expect(facts.stay.arrangement == .booked)
    #expect(facts.stay.placeId == "manual:stay")
    #expect(facts.stay.checkIn == LocalTime("15:00"))
    #expect(facts.stay.checkOut == LocalTime("11:00"))
    #expect(facts.stay.timesEstimated == true)
    #expect(facts.base?.place.id == "manual:stay")
    #expect(facts.base?.kind == .stay)
    #expect(try assumptionTexts(options, facts: facts).contains(
        "Check-in 15:00 and check-out 11:00 are typical times, not from your booking. "
            + "Check them with your stay."))
}

@Test func sameDayStayIsBookedWithNoTimes() async throws {
    let fetcher = PlaceSearchFake(answers: ["Hotel": found("Example Hotel", latitude: "53.7950",
                                                           longitude: "-1.5500")])
    let options = try options(stay: "Example Hotel")
    let facts = try await baseFacts(options, fetcher: fetcher)
    #expect(facts.stay.arrangement == .booked)
    #expect(facts.stay.placeId == "manual:stay")
    #expect(facts.stay.checkIn == nil && facts.stay.checkOut == nil && facts.stay.timesEstimated == nil)
    #expect(facts.base?.place.id == "manual:stay")
    #expect(try assumptionTexts(options, facts: facts).allSatisfy { !$0.contains("15:00") })
}

@Test func multiDayTripWithNoStayHasNoStayPlaceAndNoBase() async throws {
    let fetcher = PlaceSearchFake(answers: [:])
    let options = try options(to: "2026-11-15")
    let facts = try await baseFacts(options, fetcher: fetcher)
    #expect(facts.stay.arrangement == .unknown)
    #expect(facts.stay.placeId == nil)
    #expect(facts.places.values.allSatisfy { $0.kind != .lodging })
    #expect(facts.base == nil)
    #expect(try assumptionTexts(options, facts: facts).isEmpty)
}

// MARK: Measurements

@Test func walksAreMeasuredFromTheBaseAndNothingWithoutOne() async throws {
    let fetcher = PlaceSearchFake(answers: ["railway": station])
    let facts = try await baseFacts(try options(travel: .train), fetcher: fetcher)
    let (measurements, walks) = try await SourcePreparation.measure(
        facts, geocoder: NominatimGeocoder(fetcher: fetcher, interval: .zero))
    let hub = try #require(facts.base?.place)
    #expect(Set(walks.keys) == Set(facts.places.keys))
    for (id, place) in facts.places {
        #expect(walks[id] == StraightLineWalkTimes().minutes(from: hub.location.coordinate,
                                                            to: place.location.coordinate))
    }
    #expect(measurements.walkFromBase == walks)

    let bare = try await baseFacts(try options(to: "2026-11-15"), fetcher: PlaceSearchFake(answers: [:]))
    let (bareMeasurements, bareWalks) = try await SourcePreparation.measure(
        bare, geocoder: NominatimGeocoder(fetcher: fetcher, interval: .zero))
    #expect(bareWalks.isEmpty)
    #expect(bareMeasurements.walkFromBase.isEmpty)
}

/// A way of travel, the word that finds its hub on the map, and the hub's name.
private struct HubCase {
    let mode: TravelMode
    let keyword: String
    let name: String
}
