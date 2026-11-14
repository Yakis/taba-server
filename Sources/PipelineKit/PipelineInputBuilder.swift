// swiftlint:disable file_length
import Foundation
import GuideKit
import ResponsesKit
import SourcesKit

/// Independent measured inputs. Area integration can populate these without coupling the builders to clustering.
public struct PipelineInputMeasurements: Sendable {
    public let areas: [String: String]
    public let areaLabels: [String: String]
    public let walkFromBase: [String: Int]
    public let areaWalkMinutes: JSONValue
    public let alwaysOpenPlaceIDs: Set<String>
    /// Walk from the arrival to the first planned stop and from the last stop to departure.
    public let arrivalWalkMinutes: Int
    public let departureWalkMinutes: Int
    public let arrivalMarginMinutes: Int
    public let departureMarginMinutes: Int
    /// The interest searches that found each place, by place id: the labels of `InterestSearches`, sorted. Places
    /// found by no interest search are absent.
    public let searchLabels: [String: [String]]

    public init(areas: [String: String], walkFromBase: [String: Int], areaWalkMinutes: JSONValue,
                arrivalWalkMinutes: Int, departureWalkMinutes: Int,
                arrivalMarginMinutes: Int = 0, departureMarginMinutes: Int = 30,
                alwaysOpenPlaceIDs: Set<String> = [], searchLabels: [String: [String]] = [:]) {
        self.areas = areas
        self.areaLabels = areas
        self.walkFromBase = walkFromBase
        self.areaWalkMinutes = areaWalkMinutes
        self.alwaysOpenPlaceIDs = alwaysOpenPlaceIDs
        self.arrivalWalkMinutes = arrivalWalkMinutes
        self.departureWalkMinutes = departureWalkMinutes
        self.arrivalMarginMinutes = arrivalMarginMinutes
        self.departureMarginMinutes = departureMarginMinutes
        self.searchLabels = searchLabels
    }

    /// Reconstructs a measured input without losing the distinction between area IDs and labels.
    public init(areas: [String: String], areaLabels: [String: String], walkFromBase: [String: Int],
                areaWalkMinutes: JSONValue, alwaysOpenPlaceIDs: Set<String>, arrivalWalkMinutes: Int,
                departureWalkMinutes: Int, arrivalMarginMinutes: Int, departureMarginMinutes: Int,
                searchLabels: [String: [String]] = [:]) {
        self.areas = areas
        self.areaLabels = areaLabels
        self.walkFromBase = walkFromBase
        self.areaWalkMinutes = areaWalkMinutes
        self.alwaysOpenPlaceIDs = alwaysOpenPlaceIDs
        self.arrivalWalkMinutes = arrivalWalkMinutes
        self.departureWalkMinutes = departureWalkMinutes
        self.arrivalMarginMinutes = arrivalMarginMinutes
        self.departureMarginMinutes = departureMarginMinutes
        self.searchLabels = searchLabels
    }

    public init(areas: Areas, places: [String: Place], baseWalks: [String: Int],
                arrivalWalkMinutes: Int, departureWalkMinutes: Int,
                arrivalMarginMinutes: Int = 0, departureMarginMinutes: Int = 30,
                alwaysOpenPlaceIDs: Set<String> = [], searchLabels: [String: [String]] = [:]) {
        var ids: [String: String] = [:]
        var labels: [String: String] = [:]
        var matrix: [String: [String: JSONValue]] = [:]
        for cluster in areas.clusters {
            matrix[cluster.id] = [cluster.id: .integer(0)]
            for id in cluster.candidateIDs where places[id] != nil {
                ids[id] = cluster.id
                labels[id] = cluster.name ?? cluster.id
            }
        }
        for walk in areas.walks {
            matrix[walk.fromAreaID, default: [:]][walk.toAreaID] = .integer(walk.minutes)
        }
        self.areas = ids
        self.areaLabels = labels
        self.walkFromBase = baseWalks
        self.areaWalkMinutes = .object(matrix.mapValues { .object($0) })
        self.arrivalWalkMinutes = arrivalWalkMinutes
        self.departureWalkMinutes = departureWalkMinutes
        self.arrivalMarginMinutes = arrivalMarginMinutes
        self.departureMarginMinutes = departureMarginMinutes
        self.alwaysOpenPlaceIDs = alwaysOpenPlaceIDs
        self.searchLabels = searchLabels
    }
}

public enum PipelineInputError: Error, Equatable {
    case invalidDateRange
    case invalidWindow(LocalDate)
    case missingArea(String)
    case missingWalk(String)
    case missingPlace(String)
    case invalidTimeZone(String)
    case invalidMeasurement
    case missingLeg(String)
    case invalidUTF8
}

/// A conversation can be passed to a future Responses transport without losing repair history.
public enum PipelineMessageRole: String, Sendable, Codable { case user, assistant }

public struct PipelineConversation: Sendable, Equatable, Codable {
    public struct Message: Sendable, Equatable, Codable {
        public let role: PipelineMessageRole
        public let content: String
        public init(role: PipelineMessageRole, content: String) { self.role = role; self.content = content }
    }
    public let instructions: String
    public let messages: [Message]
    public init(instructions: String, messages: [Message]) {
        self.instructions = instructions
        self.messages = messages
    }
    public func appendingRepair(previousAssistant: String, repairText: String, payload: String) -> Self {
        Self(instructions: instructions, messages: messages + [
            Message(role: .assistant, content: previousAssistant),
            Message(role: .user, content: repairText + "\n\n" + payload)
        ])
    }
}

/// Builds the exact JSON values sent to the prompts. Serialize with `json` for deterministic key order.
public enum PipelineInputBuilder {
    public static func json(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let text = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw PipelineInputError.invalidUTF8
        }
        return text
    }

    private static func value<T: Encodable>(_ item: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(item))
    }
    private static func optional<T: Encodable>(_ item: T?) throws -> JSONValue {
        guard let item else { return .null }
        return try value(item)
    }
    private static func dates(_ trip: Trip) throws -> [LocalDate] {
        guard trip.dates.start <= trip.dates.end else { throw PipelineInputError.invalidDateRange }
        var date = trip.dates.start
        var result: [LocalDate] = []
        while date <= trip.dates.end {
            result.append(date)
            if date == trip.dates.end { break }
            guard let next = date.adding(days: 1), next > date else { throw PipelineInputError.invalidDateRange }
            date = next
        }
        return result
    }
    private static func trip(_ trip: Trip, writing: Bool, locale: String) throws -> JSONValue {
        var object: [String: JSONValue] = [
            "destination": try value(trip.destination), "dates": try value(trip.dates),
            "party": try value(trip.party), "pace": try value(trip.pace),
            "interests": try value(trip.interests)
        ]
        if writing {
            object["voice"] = .string(trip.voice)
            object["locale"] = .string(locale)
        } else {
            object["dailySpend"] = try value(trip.budget.dailySpend)
        }
        return .object(object)
    }

    public static func research(trip: Trip, stayArea: String) throws -> JSONValue {
        .object(["destination": try value(trip.destination), "dates": try value(trip.dates),
                 "stayArea": .string(stayArea), "interests": try value(trip.interests),
                 "dailySpend": try value(trip.budget.dailySpend)])
    }

    /// Hours include the previous day's carry-over, except where today's explicit closure overrides it.
    public static func hours(_ hours: OpeningHours, on date: LocalDate, always: Bool = false) -> JSONValue {
        let exception = hours.exceptions.first { $0.date == date }
        if exception?.closed == true { return .string("closed") }
        if always && exception == nil { return .string("always") }
        if !hours.hoursKnown && exception == nil { return .string("unknown") }
        func periods(_ day: LocalDate) -> [TimePeriod] {
            if let exception = hours.exceptions.first(where: { $0.date == day }) {
                return exception.closed ? [] : exception.periods
            }
            return hours.weekly.filter { $0.weekday == day.weekday }.map { TimePeriod(open: $0.open, close: $0.close) }
        }
        if hours.exceptions.contains(where: { $0.date == date && $0.closed }) { return .string("closed") }
        var result = periods(date).map { "\($0.open)-\($0.close)" }
        if exception == nil, let previous = date.adding(days: -1) {
            result += periods(previous).filter { $0.close <= $0.open && $0.close.minutesSinceMidnight > 0 }
                .map { "00:00-\($0.close)" }
        }
        if result.contains("00:00-00:00") { return .string("always") }
        return result.isEmpty ? .string("closed") : .array(result.sorted().map { .string($0) })
    }

    private static func findings(_ findings: [ResearchFinding]) throws -> JSONValue {
        .array(try findings.map { finding in
            var fields = try value(finding).objectValue ?? [:]
            fields.removeValue(forKey: "summary")
            fields.removeValue(forKey: "title")
            fields.removeValue(forKey: "times")
            fields.removeValue(forKey: "placeName")
            fields.removeValue(forKey: "address")
            fields.removeValue(forKey: "sourceTitle")
            fields["startDate"] = try optional(finding.startDate)
            fields["endDate"] = try optional(finding.endDate)
            fields["external"] = .object([
                "title": .string(finding.title), "summary": .string(finding.summary),
                "times": try optional(finding.times), "placeName": try optional(finding.placeName),
                "address": try optional(finding.address), "sourceTitle": .string(finding.sourceTitle)
            ])
            return .object(fields)
        })
    }

    private static func anchors(_ guide: Guide) throws -> JSONValue {
        let bookings: [JSONValue] = try guide.bookings.map { booking in
            var fields = try value(booking).objectValue ?? [:]
            fields.removeValue(forKey: "notes")
            fields["external"] = .object(["notes": try optional(booking.notes)])
            return .object(fields)
        }
        return .object(["bookings": .array(bookings), "stay": try stayAnchor(guide),
                        "travel": travelAnchor(guide.trip.travel), "base": baseAnchor(guide.base)])
    }
    /// The stay as the guide now reads it. Every key is present. The arrangement is the effective one, so old guides
    /// and facts seeds that carry no `arrangement` still read as booked when they name a stay.
    private static func stayAnchor(_ guide: Guide) throws -> JSONValue {
        let stay = guide.stay
        return .object([
            "arrangement": .string(guide.stayArrangement.rawValue),
            "placeId": stringValue(guide.stayPlace?.id),
            "checkIn": try optional(stay.checkIn),
            "checkOut": try optional(stay.checkOut),
            "timesEstimated": .bool(stay.timesEstimated ?? false),
            "luggage": try optional(stay.luggage),
            "handLuggageOnly": .bool(stay.handLuggageOnly ?? false)
        ])
    }
    /// How the traveller reaches the city and leaves it, or null when they did not say.
    private static func travelAnchor(_ travel: TripTravel?) -> JSONValue {
        guard let travel else { return .null }
        return .object(["mode": .string(travel.mode.rawValue), "arrivalPlaceId": stringValue(travel.arrivalPlaceId),
                        "departurePlaceId": stringValue(travel.departurePlaceId)])
    }
    /// The place distances are measured from, and how the guide names it. Null when there is none.
    private static func baseAnchor(_ base: GuideBase?) -> JSONValue {
        guard let base else { return .null }
        let kind: String
        switch base.kind {
        case .stay: kind = "stay"
        case .arrival: kind = "arrival"
        }
        return .object(["placeId": .string(base.place.id), "kind": .string(kind), "phrase": .string(base.phrase)])
    }
    private static func stringValue(_ text: String?) -> JSONValue {
        text.map(JSONValue.string) ?? .null
    }
    private static func weather(_ day: DayWeather?) -> JSONValue {
        guard let day else { return .null }
        return .object(["rainChance": day.rainChance.map(JSONValue.integer) ?? .null,
                        "tempMax": day.tempMax.map(JSONValue.number) ?? .null,
                        "tempMin": day.tempMin.map(JSONValue.number) ?? .null,
                        "summary": .string(day.summary), "isForecast": .bool(day.isForecast)])
    }
    private static func light(_ date: LocalDate, trip: Trip, weather: [DayWeather]) throws -> [String: JSONValue] {
        guard let sun = SunTimes.compute(date: date, at: trip.destination.centre,
                                         timeZoneId: trip.destination.timeZoneId) else {
            throw PipelineInputError.invalidTimeZone(trip.destination.timeZoneId)
        }
        return ["date": try value(date), "sunrise": try optional(sun.sunrise),
                "sunset": try optional(sun.sunset), "blueHourEnds": try optional(sun.blueHourEnds),
                "weather": self.weather(weather.first { $0.date == date })]
    }
    /// A walk or bus or taxi ride, as `{"mode": ..., "minutes": ...}`.
    private static func travelValue(mode: LegMode, minutes: Int) -> JSONValue {
        .object(["mode": .string(mode.rawValue), "minutes": .integer(minutes)])
    }
    /// The walk, or bus or taxi ride, from the base to a candidate.
    private static func travelFromBase(walk: Int, to place: Place, origin: Place) -> JSONValue {
        let leg = Travel.leg(walkMinutes: walk, metres: Travel.metres(from: origin.location.coordinate,
                                                                    to: place.location.coordinate))
        return travelValue(mode: leg.mode, minutes: leg.minutes)
    }
    // Interests are only for the plan's candidates, so the writer's input is unchanged.
    // With no base, `fromBase` is null and no walk is required.
    private static func place(_ place: Place, dates: [LocalDate], measurements: PipelineInputMeasurements,
                              writing: Bool, base: GuideBase?, interests: [String] = []) throws -> JSONValue {
        guard let area = measurements.areas[place.id] else { throw PipelineInputError.missingArea(place.id) }
        let fromBase: JSONValue
        if let base {
            guard let walk = measurements.walkFromBase[place.id], walk >= 0 else {
                throw PipelineInputError.missingWalk(place.id)
            }
            fromBase = travelFromBase(walk: walk, to: place, origin: base.place)
        } else {
            fromBase = .null
        }
        let hoursByDate = Dictionary(uniqueKeysWithValues: dates.map {
            ($0.description, hours(place.hours, on: $0, always: measurements.alwaysOpenPlaceIDs.contains(place.id)))
        })
        var result: [String: JSONValue] = [
            "id": .string(place.id), "name": .string(place.name), "kind": try value(place.kind),
            "area": .string(area), "areaName": .string(measurements.areaLabels[place.id] ?? area),
            "fromBase": fromBase, "hours": .object(hoursByDate),
            "priceLevel": try optional(place.priceLevel), "bookingNeeded": .bool(place.booking.needed),
            "indoor": .bool(place.indoor)
        ]
        if writing {
            result["address"] = try optional(place.location.address)
            result["external"] = .object(["facts": try value(place.facts)])
        } else {
            result.merge(planFields(place, interests: interests, measurements: measurements)) { _, new in new }
        }
        return .object(result)
    }
    public static func plan(guide: Guide, measurements: PipelineInputMeasurements, weather: [DayWeather],
                            findings research: [ResearchFinding], requests: JSONValue) throws -> JSONValue {
        let dates = try dates(guide.trip)
        let days: [JSONValue] = try dates.map { date in
            var result = try light(date, trip: guide.trip, weather: weather)
            result["weekday"] = try value(date.weekday)
            result["window"] = try window(date, guide: guide, measurements: measurements)
            return .object(result)
        }
        let base = guide.base
        let places = try rankedCandidates(guide, measurements: measurements).map {
            try place($0, dates: dates, measurements: measurements, writing: false, base: base,
                      interests: guide.trip.interests)
        }
        return .object(["trip": try trip(guide.trip, writing: false, locale: ""), "anchors": try anchors(guide),
                        "days": .array(days), "areaTravelMinutes": measurements.areaWalkMinutes,
                        "candidates": .array(places), "findings": try findings(research), "requests": requests])
    }
    // Locale and research are independent of the checked plan and its measurements.
    // swiftlint:disable:next function_parameter_count
    public static func write(
        guide: Guide, draft: PlanDraft, measurements: PipelineInputMeasurements,
        weather: [DayWeather], findings research: [ResearchFinding], locale: String
    ) throws -> JSONValue {
        let dates = try dates(guide.trip)
        let days: [JSONValue] = try draft.days.map { day in
            guard let assembledDay = guide.days.first(where: { $0.date == day.date }),
                  assembledDay.stops.count == day.stops.count else {
                throw PipelineInputError.missingLeg(day.date.description)
            }
            let ordered = day.stops.enumerated().sorted {
                $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start
            }.map(\.element)
            let stops: [JSONValue] = try zip(ordered, assembledDay.stops).map { stop, assembled in
                guard stop.start == assembled.start, stop.placeId == assembled.placeId else {
                    throw PipelineInputError.missingLeg(stop.id)
                }
                var fields = try value(stop).objectValue ?? [:]
                fields["placeId"] = try optional(stop.placeId)
                fields["mealSlot"] = try optional(stop.mealSlot)
                fields["alternative"] = try optional(stop.alternative)
                fields["fromPrevious"] = assembled.legFromPrevious
                    .map { travelValue(mode: $0.mode, minutes: $0.minutes) } ?? .null
                return .object(fields)
            }
            return .object(["date": try value(day.date), "theme": .string(day.theme), "stops": .array(stops)])
        }
        let ids = Set(draft.days.flatMap(\.stops).flatMap { [$0.placeId, $0.alternative?.placeId].compactMap { $0 } }
                      + draft.lists.flatMap(\.placeIds))
        let base = guide.base
        let places = try ids.sorted().map { id in
            guard let item = guide.places[id] else { throw PipelineInputError.missingPlace(id) }
            return try place(item, dates: dates, measurements: measurements, writing: true, base: base)
        }
        return .object(["trip": try trip(guide.trip, writing: true, locale: locale), "days": .array(days),
                        "light": .array(try dates.map {
                            .object(try light($0, trip: guide.trip, weather: weather))
                        }),
                        "places": .array(places), "findings": try findings(research),
                        "anchors": try anchors(guide), "lists": try value(draft.lists),
                        "openQuestions": try value(draft.openQuestions),
                        "external": .object(["practical": try value(guide.practical),
                                             "sources": try value(guide.sources)])])
    }
    public static func repair(issues: [PlanIssue], legs: JSONValue) throws -> String {
        let entries: [JSONValue] = try issues.map { issue in
            .object(["severity": try value(issue.severity), "kind": try value(issue.kind),
                     "date": try value(issue.date), "stopId": try optional(issue.stopId),
                     "message": .string(issue.message)])
        }
        return try json(.object(["issues": .array(entries), "legs": legs]))
    }
}

/// The trip window of a day, in minutes since midnight. Kept apart from the enum so its body stays short.
private extension PipelineInputBuilder {
    /// The candidates, ordered by the best trip interest each one serves (its place in the trip's list), then places
    /// research picked before the others, then by id. A candidate that serves none comes last, with research picks
    /// first among those. The planner meets the top-ranked interests first.
    static func rankedCandidates(_ guide: Guide, measurements: PipelineInputMeasurements) -> [Place] {
        let interests = guide.trip.interests
        let ranked = guide.places.values.map { place in
            (place: place, rank: bestInterestRank(place, interests: interests, measurements: measurements),
             researchOrder: isResearched(place, measurements: measurements) ? 0 : 1)
        }
        return ranked.sorted {
            ($0.rank, $0.researchOrder, $0.place.id) < ($1.rank, $1.researchOrder, $1.place.id)
        }.map(\.place)
    }

    /// Whether research picked the place by name, which is what its `researched` flag in the plan input says.
    static func isResearched(_ place: Place, measurements: PipelineInputMeasurements) -> Bool {
        (measurements.searchLabels[place.id] ?? []).contains(InterestMatch.researchLabel)
    }

    /// The fields only a plan candidate carries: the interests it serves, and `researched` when research picked it.
    static func planFields(_ place: Place, interests: [String],
                           measurements: PipelineInputMeasurements) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        let served = InterestMatch.interests(for: interests, kind: place.kind, indoor: place.indoor,
                                             searchLabels: measurements.searchLabels[place.id] ?? [])
        if !served.isEmpty { fields["interests"] = .array(served.map { .string($0) }) }
        if isResearched(place, measurements: measurements) { fields["researched"] = .bool(true) }
        return fields
    }

    /// The position in the trip's interests of the best one `place` serves, or `Int.max` when it serves none.
    static func bestInterestRank(_ place: Place, interests: [String], measurements: PipelineInputMeasurements) -> Int {
        let served = InterestMatch.interests(for: interests, kind: place.kind, indoor: place.indoor,
                                             searchLabels: measurements.searchLabels[place.id] ?? [])
        return served.compactMap { interests.firstIndex(of: $0) }.min() ?? Int.max
    }

    /// Minutes between a stated arrival and the start of the day's plan, when no transport booking gives one.
    static let arrivalBufferMinutes = 30
    /// Minutes between the end of the day's plan and a stated leaving time, when no transport booking gives one.
    static let departureBufferMinutes = 45
    /// The buffer when the departure place is known and the traveller goes by train, coach or car. The plan checker's
    /// departure check already requires each last stop to end 30 minutes plus its journey before leaving (see GuideKit
    /// `TransitChecks.departureFindings`), so the day ends where that check begins.
    static let knownDepartureBufferMinutes = 30

    /// The buffer before a stated leaving time: `knownDepartureBufferMinutes` from a known departure place by ground
    /// transport, otherwise `departureBufferMinutes`.
    static func departureBuffer(_ guide: Guide) -> Int {
        guard let travel = guide.trip.travel, travel.mode != .flight,
              let placeId = travel.departurePlaceId, guide.places[placeId] != nil else {
            return departureBufferMinutes
        }
        return knownDepartureBufferMinutes
    }

    static func window(
        _ date: LocalDate, guide: Guide, measurements: PipelineInputMeasurements
    ) throws -> JSONValue {
        let nums = [measurements.arrivalWalkMinutes, measurements.departureWalkMinutes,
                    measurements.arrivalMarginMinutes, measurements.departureMarginMinutes]
        guard nums.allSatisfy({ (0...1439).contains($0) }) else { throw PipelineInputError.invalidMeasurement }
        var start = 0
        var end = 1439
        let transit = guide.bookings.filter { [.train, .flight, .bus].contains($0.kind) }
        func local(_ id: String?, _ name: String) -> Bool {
            if let id, guide.places[id] != nil { return true }
            return name.localizedCaseInsensitiveContains(guide.trip.destination.name)
        }
        let arrivals = transit.filter { local($0.toPlaceId, $0.to) && !local($0.fromPlaceId, $0.from) }
        let departures = transit.filter { local($0.fromPlaceId, $0.from) && !local($0.toPlaceId, $0.to) }
        if date == guide.trip.dates.start,
           let arrival = arrivals.filter({ $0.arrives.date == date }).min(by: { $0.arrives < $1.arrives }) {
            start = arrival.arrives.time.minutesSinceMidnight
                + measurements.arrivalWalkMinutes + measurements.arrivalMarginMinutes
        } else if date == guide.trip.dates.start, let arrives = guide.trip.dates.arrives {
            // No arrival booking: the traveller is in the city from the stated arrival time plus a buffer.
            start = min(max(arrives.minutesSinceMidnight + arrivalBufferMinutes, 0), 1439)
        }
        if date == guide.trip.dates.end,
           let departure = departures.filter({ $0.departs.date == date }).min(by: { $0.departs < $1.departs }) {
            end = departure.departs.time.minutesSinceMidnight
                - measurements.departureWalkMinutes - measurements.departureMarginMinutes
        } else if date == guide.trip.dates.end, let leaves = guide.trip.dates.leaves {
            // No departure booking: the traveller leaves the city a buffer before the stated leaving time.
            end = min(max(leaves.minutesSinceMidnight - departureBuffer(guide), 0), 1439)
        }
        guard let first = LocalTime(minutesSinceMidnight: start),
              let last = LocalTime(minutesSinceMidnight: end), first <= last else {
            throw PipelineInputError.invalidWindow(date)
        }
        return .object(["start": try value(first), "end": try value(last)])
    }
}
