import Foundation
import GuideKit

/// The only caller-controlled inputs to a build. Provider configuration belongs to the server.
public struct TripBuildInput: Codable, Sendable {
    public let destination: String
    public let from: LocalDate
    public let to: LocalDate
    public let stay: String?
    /// Optional facts scaffold; existing plan and copy are not used by the pipeline.
    public let facts: Guide?

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidDestination, invalidStay, invalidDates, factsMismatch, tooManyFacts, unknownField
    }

    public init(destination: String, from: LocalDate, to: LocalDate, stay: String? = nil,
                facts: Guide? = nil) throws {
        guard Self.validName(destination) else { throw ValidationError.invalidDestination }
        guard stay.map(Self.validName) ?? true else { throw ValidationError.invalidStay }
        // Inclusive maximum of 14 calendar days, even around DST and month/year boundaries.
        guard from <= to, let limit = from.adding(days: 13), to <= limit else {
            throw ValidationError.invalidDates
        }
        if let facts {
            guard stay == nil, facts.trip.dates.start == from, facts.trip.dates.end == to,
                  facts.trip.destination.name.caseInsensitiveCompare(destination) == .orderedSame else {
                throw ValidationError.factsMismatch
            }
            guard facts.places.count <= 200, facts.bookings.count <= 40,
                  facts.practical.count <= 200, facts.sources.count <= 200 else {
                throw ValidationError.tooManyFacts
            }
        }
        self.destination = destination
        self.from = from
        self.to = to
        self.stay = stay
        self.facts = facts
    }

    private static func validName(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= 120
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private enum Keys: String, CodingKey, CaseIterable { case destination, from, to, stay, facts }
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: any Decoder) throws {
        let all = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Set(Keys.allCases.map(\.rawValue))
        guard all.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else { throw ValidationError.unknownField }
        let values = try decoder.container(keyedBy: Keys.self)
        try self.init(destination: values.decode(String.self, forKey: .destination),
                      from: values.decode(LocalDate.self, forKey: .from),
                      to: values.decode(LocalDate.self, forKey: .to),
                      stay: values.decodeIfPresent(String.self, forKey: .stay),
                      facts: values.decodeIfPresent(Guide.self, forKey: .facts))
    }
}
