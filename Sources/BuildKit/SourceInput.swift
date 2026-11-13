import Foundation
import GuideKit
import ResponsesKit

/// Source inputs are values, never paths or provider configuration.
public struct SourceInput: Sendable {
    public let destination: String
    public let from: LocalDate
    public let to: LocalDate
    public let stay: String?
    public let facts: Guide?
    public let preferences: TripPreferences
    /// The local time the traveller reaches the city on `from`, and leaves it on `to`. Nil when unknown.
    public let arrives: LocalTime?
    public let leaves: LocalTime?
    /// The place where bags can wait, when the traveller named one. Nil when none.
    public let luggage: String?
    /// True when the travellers carry only hand luggage. Then no luggage store is looked up or planned.
    public let handLuggageOnly: Bool
    /// How the traveller reaches the city and leaves it. Nil when not said.
    public let travelMode: TravelMode?
    /// The station, coach station, airport or car park the traveller named. Nil when they named none.
    public let travelPlace: String?

    public init(destination: String, from: LocalDate, to: LocalDate, stay: String? = nil, facts: Guide? = nil,
                preferences: TripPreferences = .standard, arrives: LocalTime? = nil, leaves: LocalTime? = nil,
                luggage: String? = nil, handLuggageOnly: Bool = false, travelMode: TravelMode? = nil,
                travelPlace: String? = nil) {
        self.destination = destination
        self.from = from
        self.to = to
        self.stay = stay
        self.facts = facts
        self.preferences = preferences
        self.arrives = arrives
        self.leaves = leaves
        self.luggage = luggage
        self.handLuggageOnly = handLuggageOnly
        self.travelMode = travelMode
        self.travelPlace = travelPlace
    }
}

public enum SourcePreparationError: Error, Sendable {
    case factsMismatch, geocoding, noCandidates, service
}

public typealias SourceEvidenceSink = @Sendable ([String: JSONValue]) async -> Void

/// Source evidence has no dependency on CLI storage.
public struct SourceRecord: Sendable {
    private let sink: SourceEvidenceSink
    public init(_ sink: @escaping SourceEvidenceSink) { self.sink = sink }
    public func append(_ fields: [String: JSONValue]) async { await sink(fields) }
    public func check() async throws {}
}

func value<T: Encodable>(_ item: T) -> JSONValue {
    guard let data = try? JSONEncoder().encode(item),
          let result = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
    return result
}
