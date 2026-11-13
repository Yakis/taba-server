import Foundation
import GuideKit
import PipelineKit
import SourcesKit

extension SourcePreparation {
    /// Walks are measured from the base: the stay the traveller named, or the arrival hub on a one-day trip. With no
    /// base there are no walks, and nothing is measured from a place the guide made up.
    public static func measure(_ facts: TripFacts, geocoder: NominatimGeocoder,
                               searchLabels: [String: [String]] = [:]) async throws
        -> (PipelineInputMeasurements, [String: Int]) {
        let places = facts.places
        let candidates = places.values.map { AreaCandidate(id: $0.id, coordinate: $0.location.coordinate) }
        let areas = try await AreaNameFallback.cluster(candidates, destination: facts.trip.destination.name) { point in
            try await geocoder.areaName(near: point, preferSuburbOrQuarter: true)
        }
        let walker = StraightLineWalkTimes()
        let walks: [String: Int]
        if let origin = facts.base?.place {
            walks = places.mapValues { walker.minutes(from: origin.location.coordinate, to: $0.location.coordinate) }
        } else {
            walks = [:]
        }
        let arrivals = facts.bookings.filter { $0.arrives.date == facts.trip.dates.start }
            .compactMap { $0.toPlaceId.flatMap { places[$0] } }
        let departures = facts.bookings.filter { $0.departs.date == facts.trip.dates.end }
            .compactMap { $0.fromPlaceId.flatMap { places[$0] } }
        func maximum(_ anchors: [Place]) -> Int {
            anchors.flatMap { anchor in places.values.map {
                walker.minutes(from: anchor.location.coordinate, to: $0.location.coordinate)
            } }.max() ?? 0
        }
        return (PipelineInputMeasurements(areas: areas, places: places, baseWalks: walks,
                    arrivalWalkMinutes: maximum(arrivals), departureWalkMinutes: maximum(departures),
                    searchLabels: searchLabels), walks)
    }
}
