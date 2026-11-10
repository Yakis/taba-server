import Foundation
import GuideKit
import ResponsesKit

/// A versioned, private checkpoint. It contains trip data and must not be logged or sent as progress.
extension ResearchedPipeline: Codable {
    private enum CodingKeys: String, CodingKey { case version, facts, measurements, research, places }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Unsupported research checkpoint version")
        }
        facts = try container.decode(FactsCheckpoint.self, forKey: .facts).value
        measurements = try container.decode(MeasurementsCheckpoint.self, forKey: .measurements).value
        verified = VerifiedResearch(result: try container.decode(ResearchResult.self, forKey: .research),
                                    places: try container.decode([Place].self, forKey: .places))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(FactsCheckpoint(facts), forKey: .facts)
        try container.encode(MeasurementsCheckpoint(measurements), forKey: .measurements)
        try container.encode(verified.result, forKey: .research)
        try container.encode(verified.places, forKey: .places)
    }
}

public struct FactsCheckpoint: Codable, Sendable {
    let trip: Trip
    let bookings: [Booking]
    let stay: Stay
    let places: [String: Place]
    let practical: [Fact]
    let sources: [Source]

    public init(_ facts: TripFacts) {
        trip = facts.trip
        bookings = facts.bookings
        stay = facts.stay
        places = facts.places
        practical = facts.practical
        sources = facts.sources
    }

    public var value: TripFacts {
        TripFacts(trip: trip, bookings: bookings, stay: stay, places: places, practical: practical, sources: sources)
    }
}

public struct MeasurementsCheckpoint: Codable, Sendable {
    let areas: [String: String]
    let areaLabels: [String: String]
    let walkFromStay: [String: Int]
    let areaWalkMinutes: JSONValue
    let alwaysOpenPlaceIDs: Set<String>
    let arrivalWalkMinutes: Int
    let departureWalkMinutes: Int
    let arrivalMarginMinutes: Int
    let departureMarginMinutes: Int
    /// Optional so that checkpoints written before this key existed still decode; nil means no interest labels.
    let searchLabels: [String: [String]]?

    public init(_ input: PipelineInputMeasurements) {
        areas = input.areas
        areaLabels = input.areaLabels
        walkFromStay = input.walkFromStay
        areaWalkMinutes = input.areaWalkMinutes
        alwaysOpenPlaceIDs = input.alwaysOpenPlaceIDs
        arrivalWalkMinutes = input.arrivalWalkMinutes
        departureWalkMinutes = input.departureWalkMinutes
        arrivalMarginMinutes = input.arrivalMarginMinutes
        departureMarginMinutes = input.departureMarginMinutes
        searchLabels = input.searchLabels
    }

    public var value: PipelineInputMeasurements {
        PipelineInputMeasurements(areas: areas, areaLabels: areaLabels, walkFromStay: walkFromStay,
                                  areaWalkMinutes: areaWalkMinutes, alwaysOpenPlaceIDs: alwaysOpenPlaceIDs,
                                  arrivalWalkMinutes: arrivalWalkMinutes, departureWalkMinutes: departureWalkMinutes,
                                  arrivalMarginMinutes: arrivalMarginMinutes,
                                  departureMarginMinutes: departureMarginMinutes,
                                  searchLabels: searchLabels ?? [:])
    }
}
