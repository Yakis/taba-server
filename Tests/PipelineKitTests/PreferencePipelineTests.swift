import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit
import Testing

/// Replies in order and keeps what was asked and reported, as the other pipeline tests do.
private actor PreferenceScript {
    private var replies: [String]
    private(set) var requests: [ResponsesRequest] = []
    private(set) var events: [PipelineEvidence] = []

    init(_ replies: [String]) { self.replies = replies }

    func send(_ request: ResponsesRequest) throws -> ResponsesResult {
        requests.append(request)
        guard !replies.isEmpty else { throw ScriptError.exhausted }
        return ResponsesResult(text: replies.removeFirst(), status: "completed", responseId: nil, usage: nil,
                               webSearchCount: 0, sourceURLs: [], citationURLs: [])
    }

    func record(_ event: PipelineEvidence) { events.append(event) }

    enum ScriptError: Error { case exhausted }
}

/// Two made-up days with hand-made places, so the plan check's interest and pace rules have something to read.
/// Nothing here is a real place.
private struct PreferenceTrip {
    let facts: TripFacts
    let measurements: PipelineInputMeasurements
    let day1: LocalDate
    let day2: LocalDate

    init(interests: [String], places: [Place]) throws {
        let start = try #require(LocalDate("2025-11-23"))
        let end = try #require(start.adding(days: 1))
        let centre = try #require(Coordinate(latitude: 55.9533, longitude: -3.1883))
        let trip = Trip(
            destination: Destination(name: "Testville", countryCode: "GB", timeZoneId: "Europe/London", centre: centre),
            dates: TripDates(start: start, end: end),
            party: Party(adults: 2, children: 0, mobilityNotes: []),
            budget: Budget(currencyCode: "GBP", stayMaxPerNight: 150, dailySpend: .moderate),
            interests: interests,
            pace: .unhurried,
            voice: "Plain."
        )
        facts = TripFacts(trip: trip, bookings: [], stay: Stay(placeId: nil, checkIn: nil, checkOut: nil,
                                                               luggage: nil, arrangement: .unknown),
                          places: Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) }),
                          practical: [], sources: [])
        measurements = PipelineInputMeasurements(
            areas: Dictionary(uniqueKeysWithValues: places.map { ($0.id, "centre") }), walkFromBase: [:],
            areaWalkMinutes: .object(["centre": .object(["centre": .integer(0)])]),
            arrivalWalkMinutes: 0, departureWalkMinutes: 0)
        day1 = start
        day2 = end
    }
}

private func alwaysOpen() throws -> OpeningHours {
    let midnight = try #require(LocalTime("00:00"))
    return OpeningHours(hoursKnown: true, weekly: Weekday.allCases.map {
        WeeklyPeriod(weekday: $0, open: midnight, close: midnight)
    }, exceptions: [])
}

private func place(_ id: String, kind: PlaceKind, indoor: Bool = true, hours: OpeningHours) throws -> Place {
    Place(id: id, name: "Test \(id)", kind: kind,
          location: PlaceLocation(coordinate: try #require(Coordinate(latitude: 55.9533, longitude: -3.1883)),
                                  address: nil, approximate: false),
          hours: hours, priceLevel: nil, booking: PlaceBooking(needed: false, url: nil), indoor: indoor,
          images: [], facts: [], copy: nil)
}

private func stop(_ id: String, _ kind: StopKind, _ placeId: String?, slot: MealSlot? = nil, _ time: String,
                  _ minutes: Int) throws -> PlanDraftStop {
    PlanDraftStop(id: id, placeId: placeId, kind: kind, mealSlot: slot, start: try #require(LocalTime(time)),
                  minutes: minutes, flexible: false, alternative: nil, reason: "Test", findingIds: [])
}

/// Breakfast, lunch and dinner with no place, as a meal may be "somewhere near".
private func meals(_ prefix: String) throws -> [PlanDraftStop] {
    [try stop("\(prefix)-breakfast", .meal, nil, slot: .breakfast, "08:30", 30),
     try stop("\(prefix)-lunch", .meal, nil, slot: .lunch, "12:00", 45),
     try stop("\(prefix)-dinner", .meal, nil, slot: .dinner, "18:30", 60)]
}

private func copy(for draft: PlanDraft, facts: TripFacts) -> GuideCopy {
    let named = Set(draft.days.flatMap(\.stops).compactMap(\.placeId) + draft.lists.flatMap(\.placeIds)).filter {
        facts.places[$0]?.kind.needsCopy == true
    }.sorted()
    return GuideCopy(
        hero: GuideHero(title: "City walks", subtitle: "A gentle wander.", tagline: "Take it easy"),
        days: draft.days.map { GuideCopyDay(date: $0.date, title: "Walk", summary: "Enjoy the day.") },
        stops: draft.days.flatMap(\.stops).map {
            GuideCopyStop(id: $0.id, title: "Stop", body: "Enjoy the stop.", actionLabel: nil)
        },
        places: named.map { GuideCopyPlace(id: $0, tag: "Local", blurb: "Enjoy a visit.") },
        lists: draft.lists.map { GuideCopyList(key: $0.key, title: "Picks", caption: "Find a place.") },
        tasting: (1...6).map { TasteItem(name: "Oats \($0)", note: "A warming dish.") },
        notes: GuideNotes(weather: "Bring a layer.", light: "Enjoy the light.",
                          backupPlan: "Take shelter.", rules: "Take your time.")
    )
}

private func json<T: Encodable>(_ value: T) throws -> String {
    try #require(String(data: JSONEncoder().encode(value), encoding: .utf8))
}

/// The three lists every plan has (`groceries` is optional). Only a cafe and a pub are named, so they fit their lists.
private func pickLists() -> [DraftList] {
    [DraftList(key: .eat, placeIds: ["manual:test-cafe"]), DraftList(key: .drink, placeIds: ["manual:test-pub-a"]),
     DraftList(key: .photos, placeIds: [])]
}

/// The three lists with no places, for a trip whose places are all viewpoints and cafes.
private func emptyLists() -> [DraftList] {
    [DraftList(key: .eat, placeIds: []), DraftList(key: .drink, placeIds: []), DraftList(key: .photos, placeIds: [])]
}

private let research = #"{"findings":[],"suggestedPlaces":[],"searchNotes":"none"}"#

struct PreferencePipelineTests {
    /// Day one serves food with one market stop and pubs with two drinks, so pubs get more main-stop time than food.
    @Test func topInterestWarningReachesTheRepairMessage() async throws {
        let hours = try alwaysOpen()
        let places = [try place("manual:test-market", kind: .market, indoor: false, hours: hours),
                      try place("manual:test-pub-a", kind: .pub, hours: hours),
                      try place("manual:test-pub-b", kind: .pub, hours: hours),
                      try place("manual:test-cafe", kind: .cafe, hours: hours)]
        let trip = try PreferenceTrip(interests: ["food", "pubs"], places: places)
        let dayOne = try meals("d1") + [
            try stop("d1-market", .sight, "manual:test-market", "10:00", 40),
            try stop("d1-pub-1", .drink, "manual:test-pub-a", "13:30", 40),
            try stop("d1-pub-2", .drink, "manual:test-pub-b", "14:30", 40),
            try stop("d1-rest", .rest, "manual:test-cafe", "15:30", 45)
        ]
        let dayTwo = try meals("d2") + [try stop("d2-rest", .rest, "manual:test-cafe", "15:00", 45)]
        let draft = PlanDraft(days: [PlanDraftDay(date: trip.day1, theme: "Walk", stops: dayOne),
                                     PlanDraftDay(date: trip.day2, theme: "Rest", stops: dayTwo)],
                              lists: pickLists(), skippedMeals: [], openQuestions: [], changes: [])
        let plan = try json(draft)
        let script = PreferenceScript([research, plan, plan, plan, try json(copy(for: draft, facts: trip.facts))])
        _ = try await GuidePipeline().run(id: "test", model: "fake", facts: trip.facts,
            measurements: trip.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })

        let rounds = await script.events.compactMap { event -> (round: Int, issues: [PlanIssue])? in
            if case let .plan(round, issues) = event { return (round, issues) }
            return nil
        }
        let first = try #require(rounds.first)
        #expect(first.round == 0)
        let outweighed = first.issues.filter { $0.kind == .topInterestOutweighed }
        #expect(outweighed.count == 1)
        #expect(outweighed.first?.severity == .warning)
        #expect(outweighed.first?.message.contains("\"pubs\" gets 80 minutes") == true)
        // The warning sends the plan back twice; the repair messages carry it.
        let requests = await script.requests
        #expect(requests.count == 5)
        #expect(requests[2].messages.last?.content.contains("topInterestOutweighed") == true)
    }

    /// Two full days with two main stops each, which is under the unhurried pace: only information, so no repair.
    @Test func informationOnlyPlanIsAcceptedWithoutRepair() async throws {
        let hours = try alwaysOpen()
        let unknown = OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
        let places = [try place("manual:test-view-a", kind: .viewpoint, indoor: false, hours: unknown),
                      try place("manual:test-view-b", kind: .viewpoint, indoor: false, hours: unknown),
                      try place("manual:test-cafe", kind: .cafe, hours: hours)]
        let trip = try PreferenceTrip(interests: ["museums"], places: places)
        let dayOne = try meals("d1") + [
            try stop("d1-view-a", .sight, "manual:test-view-a", "10:00", 40),
            try stop("d1-view-b", .sight, "manual:test-view-b", "13:45", 40),
            try stop("d1-rest", .rest, "manual:test-cafe", "15:00", 45)
        ]
        let dayTwo = try meals("d2") + [try stop("d2-rest", .rest, "manual:test-cafe", "15:00", 45)]
        let draft = PlanDraft(days: [PlanDraftDay(date: trip.day1, theme: "Walk", stops: dayOne),
                                     PlanDraftDay(date: trip.day2, theme: "Rest", stops: dayTwo)],
                              lists: emptyLists(), skippedMeals: [], openQuestions: [], changes: [])
        let script = PreferenceScript([research, try json(draft), try json(copy(for: draft, facts: trip.facts))])
        _ = try await GuidePipeline().run(id: "test", model: "fake", facts: trip.facts,
            measurements: trip.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })

        #expect(await script.requests.count == 3)
        let rounds = await script.events.compactMap { event -> [PlanIssue]? in
            if case let .plan(round, issues) = event, round == 0 { return issues }
            return nil
        }
        let issues = try #require(rounds.first)
        #expect(issues.filter { $0.kind == .mainStopsUnderPace }.count == 2)
        #expect(issues.allSatisfy { $0.severity == .info })
    }

    /// Candidates come in the order of the best trip interest they serve, then by id. Here the top interest is
    /// pubs, then food, then none: the museum with the earliest id still comes last.
    @Test func candidatesAreOrderedByTheirBestInterestRank() throws {
        let hours = try alwaysOpen()
        let places = [try place("manual:a-museum", kind: .museum, hours: hours),
                      try place("manual:test-market", kind: .market, indoor: false, hours: hours),
                      try place("manual:test-cafe", kind: .cafe, hours: hours),
                      try place("manual:test-pub", kind: .pub, hours: hours)]
        let trip = try PreferenceTrip(interests: ["pubs", "food"], places: places)
        let scaffold = Guide(id: "test", version: 1, status: .draft, trip: trip.facts.trip, bookings: [],
                             stay: trip.facts.stay, places: trip.facts.places, days: [], lists: [], tasting: [],
                             practical: [], sources: [])
        let input = try PipelineInputBuilder.plan(guide: scaffold, measurements: trip.measurements, weather: [],
                                                  findings: [], requests: .object([:]))
        let ids = (input.objectValue?["candidates"]?.arrayValue ?? []).compactMap { $0.objectValue?["id"]?.stringValue }
        #expect(ids == ["manual:test-pub", "manual:test-cafe", "manual:test-market", "manual:a-museum"])
    }
}
