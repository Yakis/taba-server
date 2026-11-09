import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit

/// Explicit representations avoid making shared source models implicitly Codable.
public struct FactsSnapshot: Codable, Sendable {
    public let trip: Trip
    public let bookings: [Booking]
    public let stay: Stay
    public let places: [String: Place]
    public let practical: [Fact]
    public let sources: [Source]
    public init(_ facts: TripFacts) {
        trip = facts.trip; bookings = facts.bookings; stay = facts.stay
        places = facts.places; practical = facts.practical; sources = facts.sources
    }
    public var value: TripFacts {
        TripFacts(trip: trip, bookings: bookings, stay: stay, places: places, practical: practical, sources: sources)
    }
}

public struct WeatherSnapshot: Codable, Sendable {
    public let date: LocalDate
    public let rainChance: Int?
    public let tempMax: Double?
    public let tempMin: Double?
    public let summary: String
    public let isForecast: Bool
    public init(_ day: DayWeather) {
        date = day.date; rainChance = day.rainChance; tempMax = day.tempMax; tempMin = day.tempMin
        summary = day.summary; isForecast = day.isForecast
    }
    public var value: DayWeather {
        DayWeather(date: date, rainChance: rainChance, tempMax: tempMax, tempMin: tempMin,
                   summary: summary, isForecast: isForecast)
    }
}

public struct MeasurementsSnapshot: Codable, Sendable {
    public let areas: [String: String]
    public let areaLabels: [String: String]
    public let walkFromStay: [String: Int]
    public let areaWalkMinutes: JSONValue
    public let alwaysOpenPlaceIDs: Set<String>
    public let arrivalWalkMinutes: Int
    public let departureWalkMinutes: Int
    public let arrivalMarginMinutes: Int
    public let departureMarginMinutes: Int
    public init(_ input: PipelineInputMeasurements) {
        areas = input.areas; areaLabels = input.areaLabels; walkFromStay = input.walkFromStay
        areaWalkMinutes = input.areaWalkMinutes; alwaysOpenPlaceIDs = input.alwaysOpenPlaceIDs
        arrivalWalkMinutes = input.arrivalWalkMinutes; departureWalkMinutes = input.departureWalkMinutes
        arrivalMarginMinutes = input.arrivalMarginMinutes; departureMarginMinutes = input.departureMarginMinutes
    }
    public var value: PipelineInputMeasurements {
        PipelineInputMeasurements(areas: areas, areaLabels: areaLabels, walkFromStay: walkFromStay,
                                  areaWalkMinutes: areaWalkMinutes, alwaysOpenPlaceIDs: alwaysOpenPlaceIDs,
                                  arrivalWalkMinutes: arrivalWalkMinutes, departureWalkMinutes: departureWalkMinutes,
                                  arrivalMarginMinutes: arrivalMarginMinutes,
                                  departureMarginMinutes: departureMarginMinutes)
    }
}

public struct BasicsCheckpoint: Codable, Sendable {
    public let facts: FactsSnapshot
    public let weather: [WeatherSnapshot]
    public let today: LocalDate
    public init(facts: TripFacts, weather: [DayWeather], today: LocalDate) {
        self.facts = FactsSnapshot(facts); self.weather = weather.map(WeatherSnapshot.init); self.today = today
    }
}

public struct CandidatesCheckpoint: Codable, Sendable {
    public let facts: FactsSnapshot
    public let measurements: MeasurementsSnapshot
    public let weather: [WeatherSnapshot]
    public let stayArea: String
    public init(_ prepared: Prepared) {
        self.init(facts: prepared.facts, measurements: prepared.measurements,
                  weather: prepared.weather, stayArea: prepared.stayArea)
    }
    public init(facts: TripFacts, measurements: PipelineInputMeasurements, weather: [DayWeather], stayArea: String) {
        self.facts = FactsSnapshot(facts); self.measurements = MeasurementsSnapshot(measurements)
        self.weather = weather.map(WeatherSnapshot.init); self.stayArea = stayArea
    }
}
