import Foundation
import GuideKit

/// The only caller-controlled inputs to a build. Provider configuration belongs to the server: the server owns
/// the connection and the list of models, and the traveller only picks one of the models it offers.
public struct TripBuildInput: Codable, Sendable {
    public let destination: String
    public let from: LocalDate
    public let to: LocalDate
    public let stay: String?
    /// Optional facts scaffold; existing plan and copy are not used by the pipeline.
    public let facts: Guide?
    /// Optional traveller preferences. Nil means the pipeline's standard value for that field.
    public let pace: Pace?
    /// Ranked interests, most important first.
    public let interests: [String]?
    public let dailySpend: DailySpend?
    public let adults: Int?
    public let children: Int?
    public let mobilityNotes: [String]?
    /// The AI model slug to build with, such as gpt-6.1-terra or claude-opus-5-5. Nil means the server default.
    public let model: String?
    /// The local time the traveller reaches the city on the first day. Nil when unknown.
    public let arrives: LocalTime?
    /// The local time the traveller leaves the city on the last day. Nil when unknown.
    public let leaves: LocalTime?
    /// The place where bags can wait, such as a station's left luggage or a hotel that keeps bags. Nil when none.
    public let luggage: String?

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidDestination, invalidStay, invalidDates, factsMismatch, tooManyFacts, unknownField
        case invalidInterests, invalidParty, invalidMobility, preferencesWithFacts, invalidModel, invalidTimes
        case invalidLuggage
    }

    public init(destination: String, from: LocalDate, to: LocalDate, stay: String? = nil,
                facts: Guide? = nil, pace: Pace? = nil, interests: [String]? = nil,
                dailySpend: DailySpend? = nil, adults: Int? = nil, children: Int? = nil,
                mobilityNotes: [String]? = nil, model: String? = nil,
                arrives: LocalTime? = nil, leaves: LocalTime? = nil, luggage: String? = nil) throws {
        guard Self.validName(destination) else { throw ValidationError.invalidDestination }
        guard model.map({ ModelChoice.isWellFormed($0) }) ?? true else { throw ValidationError.invalidModel }
        try Self.validatePlaces(stay: stay, luggage: luggage)
        // Inclusive maximum of 14 calendar days, even around DST and month/year boundaries.
        guard from <= to, let limit = from.adding(days: 13), to <= limit else {
            throw ValidationError.invalidDates
        }
        try Self.validatePreferences(interests: interests, adults: adults, children: children,
                                     mobilityNotes: mobilityNotes)
        // Stated times are preferences too: a facts seed already says when the traveller is in the city.
        let hasPreferences = pace != nil || interests != nil || dailySpend != nil
            || adults != nil || children != nil || mobilityNotes != nil || arrives != nil || leaves != nil
            || luggage != nil
        // On a one-day trip, the traveller must have at least two hours there between arriving and leaving.
        if let arrives, let leaves, from == to {
            guard leaves.minutesSinceMidnight - arrives.minutesSinceMidnight >= 120 else {
                throw ValidationError.invalidTimes
            }
        }
        if let facts {
            // Facts carry their own trip, so preferences cannot also be supplied.
            guard !hasPreferences else { throw ValidationError.preferencesWithFacts }
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
        self.pace = pace
        self.interests = interests
        self.dailySpend = dailySpend
        self.adults = adults
        self.children = children
        self.mobilityNotes = mobilityNotes
        self.model = model
        self.arrives = arrives
        self.leaves = leaves
        self.luggage = luggage
    }

    /// The same input with the model resolved, so the stored trip records the model its build will use even if the
    /// server's default changes while it waits. Returns `self` when the model is not one a trip may name.
    public func resolvingModel(_ resolved: String) -> TripBuildInput {
        guard model == nil else { return self }
        return (try? TripBuildInput(destination: destination, from: from, to: to, stay: stay, facts: facts,
                                    pace: pace, interests: interests, dailySpend: dailySpend, adults: adults,
                                    children: children, mobilityNotes: mobilityNotes, model: resolved,
                                    arrives: arrives, leaves: leaves, luggage: luggage)) ?? self
    }

    /// The places a trip may name: where it stays, and where bags can wait.
    private static func validatePlaces(stay: String?, luggage: String?) throws {
        guard stay.map({ validName($0) }) ?? true else { throw ValidationError.invalidStay }
        guard luggage.map({ validName($0) }) ?? true else { throw ValidationError.invalidLuggage }
    }

    private static func validatePreferences(interests: [String]?, adults: Int?, children: Int?,
                                            mobilityNotes: [String]?) throws {
        // Interests are ranked: order is kept, and the same interest may not appear twice.
        if let interests {
            guard interests.count <= 10, interests.allSatisfy({ validName($0, maxBytes: 60) }),
                  Set(interests.map { $0.lowercased() }).count == interests.count else {
                throw ValidationError.invalidInterests
            }
        }
        guard adults.map({ (1...10).contains($0) }) ?? true,
              children.map({ (0...10).contains($0) }) ?? true else {
            throw ValidationError.invalidParty
        }
        guard mobilityNotes.map({ notes in
            notes.count <= 5 && notes.allSatisfy({ validName($0) })
        }) ?? true else {
            throw ValidationError.invalidMobility
        }
    }

    private static func validName(_ value: String, maxBytes: Int = 120) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= maxBytes
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private enum Keys: String, CodingKey, CaseIterable {
        case destination, from, to, stay, facts
        case pace, interests, dailySpend, adults, children, mobilityNotes, model, arrives, leaves, luggage
    }
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
                      facts: values.decodeIfPresent(Guide.self, forKey: .facts),
                      pace: values.decodeIfPresent(Pace.self, forKey: .pace),
                      interests: values.decodeIfPresent([String].self, forKey: .interests),
                      dailySpend: values.decodeIfPresent(DailySpend.self, forKey: .dailySpend),
                      adults: values.decodeIfPresent(Int.self, forKey: .adults),
                      children: values.decodeIfPresent(Int.self, forKey: .children),
                      mobilityNotes: values.decodeIfPresent([String].self, forKey: .mobilityNotes),
                      model: values.decodeIfPresent(String.self, forKey: .model),
                      arrives: values.decodeIfPresent(LocalTime.self, forKey: .arrives),
                      leaves: values.decodeIfPresent(LocalTime.self, forKey: .leaves),
                      luggage: values.decodeIfPresent(String.self, forKey: .luggage))
    }
}
