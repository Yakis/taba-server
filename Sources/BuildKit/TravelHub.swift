import Foundation
import GuideKit
import SourcesKit

/// What the travel hub lookup found. A hub that cannot be found never fails the build, unlike the stay.
enum TravelHubResult {
    /// No way of travel was given, or a car with no place named: there is no hub.
    case none
    /// The hub is on the map. `typed` is true when the traveller named it.
    case found(Place, typed: Bool)
    /// The traveller named a place that is not on the map.
    case notFound(typed: String)
}

extension SourcePreparation {
    /// The id of the place where the first day starts and the last day ends, when the traveller gave a way of travel.
    static let arrivalPlaceId = "manual:arrival"

    /// The station, coach station, airport or car park where the day starts and ends. When the traveller named a
    /// place it is looked up as typed. Otherwise a train, coach or flight is looked up by its main hub in the
    /// destination, and a car has no hub unless it is named.
    static func travelHub(_ options: SourceInput, geocoder: NominatimGeocoder) async throws -> TravelHubResult {
        guard let mode = options.travelMode else { return .none }
        let kind: PlaceKind = mode == .car ? .other : .station
        if let typed = options.travelPlace {
            guard let found = try await lookUp(typed + ", " + options.destination, geocoder: geocoder) else {
                return .notFound(typed: typed)
            }
            return .found(hubPlace(name: typed, kind: kind, mode: mode, found: found), typed: true)
        }
        guard let hub = mainHub(for: mode) else { return .none }
        let query = options.destination + " " + hub.query
        guard let found = try await lookUp(query, geocoder: geocoder) else { return .none }
        let name = options.destination + " " + hub.name
        return .found(hubPlace(name: name, kind: kind, mode: mode, found: found), typed: false)
    }

    /// The search words and the name of the main hub for each way of travel, or nil for a car.
    private static func mainHub(for mode: TravelMode) -> (query: String, name: String)? {
        switch mode {
        case .train: ("railway station", "station")
        case .coach: ("coach station", "coach station")
        case .flight: ("airport", "airport")
        case .car: nil
        }
    }

    private static func hubPlace(name: String, kind: PlaceKind, mode: TravelMode, found: GeocodedPlace) -> Place {
        Place(id: arrivalPlaceId, name: name, kind: kind,
              location: PlaceLocation(coordinate: found.coordinate, address: found.displayName, approximate: false),
              hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: []), priceLevel: nil,
              booking: PlaceBooking(needed: false, url: nil), indoor: mode != .car,
              images: [], facts: [], copy: nil)
    }

    /// A failed or empty search is "not found". Cancellation still stops the build.
    private static func lookUp(_ query: String, geocoder: NominatimGeocoder) async throws -> GeocodedPlace? {
        do {
            return try await geocoder.geocode(query)
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }
}
