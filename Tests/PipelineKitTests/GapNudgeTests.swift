import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit
import Testing

/// Replies to each request in order and records what was asked and what the pipeline reported.
private actor NudgeScript {
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

    var nudges: [[String]] {
        events.compactMap { event in
            if case let .nudge(_, changes) = event { return changes }
            return nil
        }
    }

    enum ScriptError: Error { case exhausted }
}

/// Every walk takes 6 minutes, so a gap of 5 is tight (6 needed) and a gap under 10 is short.
private struct SixMinuteWalks: WalkTimes {
    func minutes(from origin: Coordinate, to destination: Coordinate) -> Int { 6 }
}

private struct Scene {
    let facts: TripFacts
    let measurements: PipelineInputMeasurements
    let day: LocalDate
    let lists: [DraftList]
}

private let research = #"{"findings":[],"suggestedPlaces":[],"searchNotes":"none"}"#

private func json<T: Encodable>(_ value: T) throws -> String {
    try #require(String(bytes: JSONEncoder().encode(value), encoding: .utf8))
}

private func time(_ text: String) throws -> LocalTime { try #require(LocalTime(text)) }

private func venue(_ id: String, closes: String = "22:00", booked: Bool = false) throws -> Place {
    let open = try time("08:00")
    let close = try time(closes)
    let weekly = Weekday.allCases.map { WeeklyPeriod(weekday: $0, open: open, close: close) }
    let coordinate = try #require(Coordinate(latitude: 55.95, longitude: -3.19))
    return Place(id: id, name: "Example \(id)", kind: .museum,
                 location: PlaceLocation(coordinate: coordinate, address: nil, approximate: false),
                 hours: OpeningHours(hoursKnown: true, weekly: weekly, exceptions: []), priceLevel: nil,
                 booking: PlaceBooking(needed: booked, url: nil), indoor: true, images: [], facts: [], copy: nil)
}

private func scene(places: [Place], tickets: [Booking] = []) throws -> Scene {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: directory.deletingLastPathComponent()
        .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")))
    let day = guide.trip.dates.start
    let trip = Trip(destination: guide.trip.destination, dates: TripDates(start: day, end: day),
                    party: guide.trip.party, budget: guide.trip.budget, interests: guide.trip.interests,
                    pace: guide.trip.pace, voice: guide.trip.voice)
    let eatKinds = try #require(PlanChecker.listKinds[.eat])
    let eat = try #require(guide.places.values.sorted { $0.id < $1.id }
        .first { $0.kind.needsCopy && eatKinds.contains($0.kind) })
    var all = guide.places
    for place in places { all[place.id] = place }
    let facts = TripFacts(trip: trip, bookings: tickets, stay: guide.stay, places: all, practical: guide.practical,
                          sources: guide.sources)
    let measurements = PipelineInputMeasurements(
        areas: all.mapValues { _ in "area" }, walkFromBase: all.mapValues { _ in 1 },
        areaWalkMinutes: .object([:]), arrivalWalkMinutes: 0, departureWalkMinutes: 0)
    let lists = [DraftList(key: .eat, placeIds: [eat.id]), DraftList(key: .drink, placeIds: []),
                 DraftList(key: .photos, placeIds: [])]
    return Scene(facts: facts, measurements: measurements, day: day, lists: lists)
}

private func stop(_ id: String, _ place: String?, _ start: String, _ minutes: Int, flexible: Bool = true,
                  kind: StopKind = .sight, slot: MealSlot? = nil) throws -> PlanDraftStop {
    PlanDraftStop(id: id, placeId: place, kind: kind, mealSlot: slot, start: try time(start), minutes: minutes,
                  flexible: flexible, alternative: nil, reason: "Visit", findingIds: [])
}

/// Three meals that need no walk, with the given sights between breakfast and lunch.
private func plan(_ scene: Scene, sights: [PlanDraftStop]) throws -> PlanDraft {
    let meals = [try stop("breakfast", nil, "09:00", 30, flexible: false, kind: .meal, slot: .breakfast),
                 try stop("lunch", nil, "12:30", 30, flexible: false, kind: .meal, slot: .lunch),
                 try stop("dinner", nil, "18:00", 30, flexible: false, kind: .meal, slot: .dinner)]
    return PlanDraft(days: [.init(date: scene.day, theme: "Walk", stops: meals + sights)], lists: scene.lists,
                     skippedMeals: [], openQuestions: [], changes: [])
}

private struct Run {
    let draft: PlanDraft
    let script: NudgeScript
}

/// Plans and checks with `first`, then replies with `repairs` if the AI is asked again.
private func run(_ scene: Scene, first: PlanDraft, repairs: [PlanDraft] = []) async throws -> Run {
    let script = try NudgeScript([research, json(first)] + repairs.map { try json($0) })
    let pipeline = GuidePipeline(walkTimes: SixMinuteWalks())
    let researched = try await pipeline.researchStage(
        model: "fake", facts: scene.facts, measurements: scene.measurements, stayArea: "Centre",
        send: { try await script.send($0) }, evidence: { await script.record($0) })
    let draft = try await pipeline.planStage(
        id: "test", model: "fake", researched: researched, weather: [],
        send: { try await script.send($0) }, evidence: { await script.record($0) })
    return Run(draft: draft, script: script)
}

private func sight(_ draft: PlanDraft, _ id: String) throws -> PlanDraftStop {
    try #require(draft.days.flatMap(\.stops).first { $0.id == id })
}

struct GapNudgeTests {
    private let first = "sight-a"
    private let second = "sight-b"
    private let third = "sight-c"

    private func places() throws -> [Place] {
        try [venue(first), venue(second), venue(third)]
    }

    @Test func shortensTheEarlierStopWithoutAskingTheAI() async throws {
        let scene = try scene(places: places())
        // 5 minutes between the two, a walk of 6, so the gap must reach 10: the first stop loses 5 minutes.
        let initial = try plan(scene, sights: [stop("a", first, "10:00", 50), stop("b", second, "10:55", 40)])
        let result = try await run(scene, first: initial)
        #expect(await result.script.requests.count == 2)
        #expect(try sight(result.draft, "a").minutes == 45)
        #expect(try sight(result.draft, "b").start == time("10:55"))
        #expect(await result.script.nudges == [["Shortened a by 5 minutes, from 50 to 45."]])
        let rounds = await result.script.events.compactMap { event -> [PlanIssue]? in
            if case let .plan(round, issues) = event, round == 0 { return issues }
            return nil
        }
        #expect(rounds.count == 1)
        #expect(rounds[0].allSatisfy { $0.severity == .info })
    }

    @Test func startsTheLaterStopLaterWhenTheEarlierOneIsTooShort() async throws {
        let scene = try scene(places: places())
        // The first stop is already at the 20-minute floor, so the second one starts 5 minutes later.
        let initial = try plan(scene, sights: [stop("a", first, "10:00", 20), stop("b", second, "10:25", 40)])
        let result = try await run(scene, first: initial)
        #expect(await result.script.requests.count == 2)
        #expect(try sight(result.draft, "a") == sight(initial, "a"))
        #expect(try sight(result.draft, "b").start == time("10:30"))
        #expect(await result.script.nudges == [["Started b 5 minutes later, at 10:30."]])
    }

    @Test func keepsThreeQuartersOfAStopWhenShortening() async throws {
        let scene = try scene(places: places())
        // Shortening a 24-minute stop by 5 would leave 19 minutes, under the 20-minute floor, so the second stop moves.
        let initial = try plan(scene, sights: [stop("a", first, "10:00", 24), stop("b", second, "10:29", 30)])
        let result = try await run(scene, first: initial)
        #expect(await result.script.requests.count == 2)
        #expect(try sight(result.draft, "a").minutes == 24)
        #expect(try sight(result.draft, "b").start == time("10:34"))
    }

    @Test(arguments: [false, true])
    func neverMovesFixedOrBookedStops(booked: Bool) async throws {
        let day = try scene(places: places()).day
        let ticket = try Booking(id: "ticket", kind: .ticket, from: "Venue", fromPlaceId: first, to: "Venue",
                                 toPlaceId: first, departs: .init(date: day, time: time("10:00")),
                                 arrives: .init(date: day, time: time("10:00")), notes: nil)
        let scene = try scene(places: places(), tickets: booked ? [ticket] : [])
        // Unbooked: the first stop is at its floor and the second is fixed. Booked: the first has a ticket.
        let minutes = booked ? 50 : 20
        let initial = try plan(scene, sights: [stop("a", first, "10:00", minutes),
                                               stop("b", second, "\(booked ? "10:55" : "10:25")", 40, flexible: false)])
        let repaired = try plan(scene, sights: [stop("a", first, "10:00", minutes),
                                                stop("b", second, "11:15", 40, flexible: false)])
        let result = try await run(scene, first: initial, repairs: [repaired])
        #expect(await result.script.requests.count == 3)
        #expect(await result.script.nudges.isEmpty)
        #expect(try sight(result.draft, "b").start == time("11:15"))
    }

    @Test func doesNotCrowdTheStopAfterTheMovedOne() async throws {
        let scene = try scene(places: places())
        // Moving b 5 minutes later would leave 5 minutes before c, and the walk of 6 wants 10.
        let initial = try plan(scene, sights: [stop("a", first, "10:00", 20), stop("b", second, "10:25", 40),
                                               stop("c", third, "11:15", 30)])
        let repaired = try plan(scene, sights: [stop("a", first, "10:00", 20), stop("b", second, "10:35", 30),
                                                stop("c", third, "11:15", 30)])
        let result = try await run(scene, first: initial, repairs: [repaired])
        #expect(await result.script.requests.count == 3)
        #expect(await result.script.nudges.isEmpty)
    }

    @Test func rejectsANudgeThatCreatesAnotherIssue() async throws {
        // The second place closes at 11:05. Starting it at 10:30 would run past closing, so the AI repairs instead.
        let scene = try scene(places: [venue(first), venue(second, closes: "11:05"), venue(third)])
        let initial = try plan(scene, sights: [stop("a", first, "10:00", 20), stop("b", second, "10:25", 40)])
        let repaired = try plan(scene, sights: [stop("a", first, "09:50", 20), stop("b", second, "10:25", 40)])
        let result = try await run(scene, first: initial, repairs: [repaired])
        #expect(await result.script.requests.count == 3)
        #expect(await result.script.nudges.isEmpty)
        #expect(try sight(result.draft, "a").start == time("09:50"))
        let firstRound = await result.script.events.compactMap { event -> [PlanIssue]? in
            if case let .plan(round, issues) = event, round == 0 { return issues }
            return nil
        }.first ?? []
        #expect(firstRound.contains { $0.kind == .tightGap && $0.severity == .error })
    }

    @Test func structuralProblemsNeverQualify() throws {
        let day = try #require(LocalDate("2026-03-02"))
        let structural = PlanIssue(severity: .error, kind: .tightGap, date: day, stopId: nil, message: "Bad plan.")
        let gap = PlanIssue(severity: .warning, kind: .shortGap, date: day, stopId: "a", message: "Short.")
        let info = PlanIssue(severity: .info, kind: .interestMissed, date: day, stopId: nil, message: "Missed.")
        #expect(!GapNudge.isGapOnly([structural]))
        #expect(!GapNudge.isGapOnly([gap, structural]))
        #expect(!GapNudge.isGapOnly([]))
        #expect(!GapNudge.isGapOnly([info]))
        #expect(GapNudge.isGapOnly([gap, info]))
        let nudge = GapNudge(facts: try scene(places: []).facts, walkTimes: SixMinuteWalks())
        #expect(nudge.apply(to: PlanDraft(days: [], lists: [], skippedMeals: [], openQuestions: [], changes: []),
                            issues: [structural]) == nil)
    }
}
