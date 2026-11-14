// swiftlint:disable file_length
import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit
import Testing

/// Replies to each request in order and records what was asked and what the pipeline reported.
private actor StayScript {
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

/// How the traveller's base is set up in a scenario.
private enum BaseKind: Equatable {
    /// A one-day trip by train, starting and ending at the station. No stay.
    case arrival
    /// A booked stay at a named hotel.
    case stay
    /// No stay and no way of travel given.
    case none
}

private struct Scenario {
    let facts: TripFacts
    let measurements: PipelineInputMeasurements
    let plan: PlanDraft
    let copy: GuideCopy
}

private let research = #"{"findings":[],"suggestedPlaces":[],"searchNotes":"none"}"#

private func json<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return try #require(String(bytes: data, encoding: .utf8))
}

private func coordinate(_ latitude: Double, _ longitude: Double) throws -> Coordinate {
    try #require(Coordinate(latitude: latitude, longitude: longitude))
}

private func makePlace(_ id: String, _ name: String, _ kind: PlaceKind, _ latitude: Double, _ longitude: Double,
                       indoor: Bool = true) throws -> Place {
    let open = try #require(LocalTime("08:00"))
    let close = try #require(LocalTime("22:00"))
    let weekly = Weekday.allCases.map { WeeklyPeriod(weekday: $0, open: open, close: close) }
    return Place(id: id, name: name, kind: kind,
          location: PlaceLocation(coordinate: try coordinate(latitude, longitude), address: nil, approximate: false),
          hours: OpeningHours(hoursKnown: true, weekly: weekly, exceptions: []), priceLevel: nil,
          booking: PlaceBooking(needed: false, url: nil), indoor: indoor, images: [], facts: [], copy: nil)
}

// swiftlint:disable:next function_parameter_count
private func stop(_ id: String, _ placeId: String?, _ kind: StopKind, slot: MealSlot? = nil, _ time: String,
                  _ minutes: Int, _ reason: String) throws -> PlanDraftStop {
    PlanDraftStop(id: id, placeId: placeId, kind: kind, mealSlot: slot, start: try #require(LocalTime(time)),
                  minutes: minutes, flexible: false, alternative: nil, reason: reason, findingIds: [])
}

// The Leeds scenario: a fixed set of candidate places around the station, the hotel, and a plan that uses each once.
// swiftlint:disable:next function_body_length
private func scenario(days count: Int, base kind: BaseKind) throws -> Scenario {
    let source = try fixtureGuide()
    let start = try #require(LocalDate("2026-11-14"))
    let end = try #require(start.adding(days: count - 1))
    let dates = try (0..<count).map { try #require(start.adding(days: $0)) }
    let oneDay = count == 1
    let station = try makePlace("manual:arrival", "Leeds station", .station, 53.7947, -1.5473)
    let hotel = try makePlace("manual:stay", "Example Hotel", .lodging, 53.7950, -1.5500)
    let cafe = try makePlace("osm:node/1", "Example Cafe", .cafe, 53.7985, -1.5440)
    let pub = try makePlace("osm:node/2", "Example Pub", .pub, 53.7970, -1.5480)
    let museum = try makePlace("osm:node/3", "Example Museum", .museum, 53.7995, -1.5460)
    let viewpoint = try makePlace("osm:node/4", "Example Viewpoint", .viewpoint, 53.8001, -1.5500, indoor: false)
    var places = [cafe, pub, museum, viewpoint]

    var travel: TripTravel?
    var arrives: LocalTime?
    var leaves: LocalTime?
    var stay = Stay(placeId: nil, checkIn: nil, checkOut: nil, luggage: nil, handLuggageOnly: nil,
                    arrangement: oneDay ? .notNeeded : .unknown, timesEstimated: nil)
    switch kind {
    case .arrival:
        places.append(station)
        travel = TripTravel(mode: .train, arrivalPlaceId: station.id, departurePlaceId: station.id)
        arrives = LocalTime("11:00")
        leaves = LocalTime("17:00")
    case .stay:
        places.append(hotel)
        var checkIn: LocalTime?
        var checkOut: LocalTime?
        if !oneDay {
            checkIn = LocalTime("15:00")
            checkOut = LocalTime("11:00")
        }
        stay = Stay(placeId: hotel.id, checkIn: checkIn, checkOut: checkOut, luggage: nil, handLuggageOnly: nil,
                    arrangement: .booked, timesEstimated: oneDay ? nil : true)
    case .none:
        break
    }
    let trip = Trip(destination: Destination(name: "Leeds", countryCode: "GB", timeZoneId: "Europe/London",
                                             centre: try coordinate(53.7997, -1.5492)),
                    dates: TripDates(start: start, end: end, arrives: arrives, leaves: leaves),
                    party: source.trip.party,
                    budget: Budget(currencyCode: "GBP", stayMaxPerNight: 0, dailySpend: source.trip.budget.dailySpend),
                    interests: source.trip.interests, pace: source.trip.pace, voice: source.trip.voice, travel: travel)
    let facts = TripFacts(trip: trip, bookings: [], stay: stay,
                          places: Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) }),
                          practical: [], sources: [])

    // Walks are measured from the base only; a trip with no base has none.
    let walker = StraightLineWalkTimes()
    let walks: [String: Int] = facts.base.map { base in
        facts.places.mapValues { walker.minutes(from: base.place.location.coordinate, to: $0.location.coordinate) }
    } ?? [:]
    let names = Dictionary(uniqueKeysWithValues: facts.places.keys.map { ($0, "Leeds centre") })
    let measurements = PipelineInputMeasurements(
        areas: names.mapValues { _ in "centre" }, areaLabels: names, walkFromBase: walks,
        areaWalkMinutes: .object(["centre": .object(["centre": .integer(0)])]), alwaysOpenPlaceIDs: [],
        arrivalWalkMinutes: 5, departureWalkMinutes: 5, arrivalMarginMinutes: 0, departureMarginMinutes: 30)

    let plan = try planDraft(dates: dates, kind: kind, cafe: cafe.id, pub: pub.id, museum: museum.id,
                             viewpoint: viewpoint.id, hotel: kind == .stay ? hotel.id : nil)
    return Scenario(facts: facts, measurements: measurements, plan: plan, copy: try copy(for: plan, facts: facts))
}

// The plan for a trip. A one-day trip by train arrives late morning and leaves in the afternoon, so it needs lunch
// only. Every other day has all its meals. Stops have room to walk between them, and a stay that
// is checked out of before lunch on the last day has a stop at the hotel first.
// swiftlint:disable:next function_parameter_count
private func planDraft(dates: [LocalDate], kind: BaseKind, cafe: String, pub: String, museum: String,
                       viewpoint: String, hotel: String?) throws -> PlanDraft {
    let arrivesByTrain = kind == .arrival
    var days: [PlanDraftDay] = []
    for (index, date) in dates.enumerated() {
        let number = index + 1
        var stops: [PlanDraftStop] = []
        if index == 0 {
            if !arrivesByTrain {
                stops.append(try stop("d\(number)-breakfast", nil, .meal, slot: .breakfast, "08:30", 30, "Breakfast"))
            }
            stops.append(try stop("d\(number)-lunch", nil, .meal, slot: .lunch, "12:00", 45, "Lunch"))
            stops.append(try stop("d\(number)-museum", museum, .sight, "13:00", 40, "Museum"))
            stops.append(try stop("d\(number)-pub", pub, .sight, "13:55", 30, "Pub"))
            stops.append(try stop("d\(number)-view", viewpoint, .sight, "14:45", 30, "View"))
            stops.append(try stop("d\(number)-cafe", cafe, .sight, "15:30", 30, "Cafe"))
            if !arrivesByTrain {
                stops.append(try stop("d\(number)-dinner", nil, .meal, slot: .dinner, "18:30", 60, "Dinner"))
            }
        } else {
            stops.append(try stop("d\(number)-breakfast", nil, .meal, slot: .breakfast, "08:30", 30, "Breakfast"))
            if let hotel {
                stops.append(try stop("d\(number)-checkout", hotel, .logistics, "10:00", 15, "Check out"))
            }
            stops.append(try stop("d\(number)-lunch", nil, .meal, slot: .lunch, "12:00", 45, "Lunch"))
            stops.append(try stop("d\(number)-dinner", nil, .meal, slot: .dinner, "18:30", 60, "Dinner"))
        }
        days.append(PlanDraftDay(date: date, theme: "Walk", stops: stops))
    }
    let skipped: [SkippedMeal] = []
    return PlanDraft(days: days,
                     lists: [DraftList(key: .eat, placeIds: [cafe]), DraftList(key: .drink, placeIds: [pub]),
                             DraftList(key: .photos, placeIds: [viewpoint]), DraftList(key: .groceries, placeIds: [])],
                     skippedMeals: skipped, openQuestions: [], changes: [])
}

/// Copy for every stop, day, list and place the plan names, with no numbers and no stay words.
private func copy(for plan: PlanDraft, facts: TripFacts) throws -> GuideCopy {
    let named = Set(plan.days.flatMap(\.stops).compactMap(\.placeId) + plan.lists.flatMap(\.placeIds))
    return GuideCopy(
        hero: GuideHero(title: "City walks", subtitle: "A gentle wander.", tagline: "Take it easy"),
        days: plan.days.map { GuideCopyDay(date: $0.date, title: "Walk", summary: "Enjoy the day.") },
        stops: (plan.days.flatMap(\.stops).map(\.id) + transitStops(facts)).map {
            GuideCopyStop(id: $0, title: "Stop", body: "Take a break here.", actionLabel: nil)
        },
        places: named.filter { facts.places[$0]?.kind.needsCopy == true }.sorted().map {
            GuideCopyPlace(id: $0, tag: "Local", blurb: "Enjoy a visit.")
        },
        lists: plan.lists.map { GuideCopyList(key: $0.key, title: "Picks", caption: "Find a place.") },
        tasting: ["Oatcakes", "Parkin", "Shortbread", "Eccles cakes", "Cranachan", "Irn-Bru"].map {
            TasteItem(name: $0, note: "A warming dish.")
        },
        notes: GuideNotes(weather: "Bring a layer.", light: "Enjoy the light.", backupPlan: "Take shelter.",
                          rules: "Take your time.")
    )
}

/// The clean copy with one stop's body replaced.
private func withBody(_ copy: GuideCopy, stop id: String, body: String) -> GuideCopy {
    GuideCopy(hero: copy.hero, days: copy.days,
              stops: copy.stops.map { $0.id == id ? GuideCopyStop(id: id, title: $0.title, body: body,
                                                                  actionLabel: $0.actionLabel) : $0 },
              places: copy.places, lists: copy.lists, tasting: copy.tasting, notes: copy.notes)
}

/// The Edinburgh fixture supplies the trip's party, budget, pace and interests, as in the other pipeline tests.
private func fixtureGuide() throws -> Guide {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
    return try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
}

/// The planner's and writer's requests in order, with the pipeline's stages run step by step.
private func researchAndPlan(_ scene: Scenario, script: StayScript) async throws -> (ResearchedPipeline, PlanDraft) {
    let pipeline = GuidePipeline()
    let researched = try await pipeline.researchStage(
        model: "fake", facts: scene.facts, measurements: scene.measurements, stayArea: "Centre",
        send: { try await script.send($0) }, evidence: { await script.record($0) })
    let draft = try await pipeline.planStage(id: "test", model: "fake", researched: researched, weather: [],
                                             send: { try await script.send($0) }, evidence: { await script.record($0) })
    return (researched, draft)
}

private func isStayContradiction(_ kind: CopyCheckIssue.Kind) -> Bool {
    if case .stayContradiction = kind { return true }
    return false
}

private func copyIssues(_ events: [PipelineEvidence]) -> [CopyCheckIssue] {
    events.flatMap { event -> [CopyCheckIssue] in
        if case let .copy(issues) = event { return issues }
        return []
    }
}

private func planIssues(_ events: [PipelineEvidence], round: Int) -> [PlanIssue] {
    events.flatMap { event -> [PlanIssue] in
        if case let .plan(found, issues) = event, found == round { return issues }
        return []
    }
}

struct StayFactsRegressionTests {
    /// The observed failure: a one-day trip by train with no stay. The guide must not invent a hotel, check-in or
    /// accommodation, and must measure from the station.
    @Test func leedsDayTripRegressionInventsNoStay() async throws {
        let scene = try scenario(days: 1, base: .arrival)
        #expect(scene.facts.places.values.allSatisfy { $0.kind != .lodging })
        #expect(scene.facts.places["manual:stay"] == nil)
        #expect(scene.facts.stay.arrangement == .notNeeded)
        #expect(scene.facts.stay.placeId == nil && scene.facts.stay.checkIn == nil && scene.facts.stay.checkOut == nil)

        // The plan input carries the arrival as the base, and every candidate is measured from the station.
        let scaffold = Guide(id: "test", version: 1, status: .draft, trip: scene.facts.trip, bookings: [],
                             stay: scene.facts.stay, places: scene.facts.places, days: [], lists: [], tasting: [],
                             practical: [], sources: [])
        let input = try PipelineInputBuilder.plan(guide: scaffold, measurements: scene.measurements, weather: [],
                                                  findings: [], requests: .object([:]))
        let anchors = try #require(input.objectValue?["anchors"]?.objectValue)
        let stayAnchor = try #require(anchors["stay"]?.objectValue)
        #expect(stayAnchor["arrangement"] == .string("notNeeded"))
        #expect(stayAnchor["placeId"] == .null && stayAnchor["checkIn"] == .null && stayAnchor["checkOut"] == .null)
        let baseAnchor = try #require(anchors["base"]?.objectValue)
        #expect(baseAnchor["kind"] == .string("arrival"))
        #expect(baseAnchor["placeId"] == .string("manual:arrival"))
        #expect(baseAnchor["phrase"] == .string("the station"))
        #expect(anchors["travel"]?.objectValue?["mode"] == .string("train"))
        let station = try #require(scene.facts.places["manual:arrival"])
        let candidates = try #require(input.objectValue?["candidates"]?.arrayValue).compactMap(\.objectValue)
        #expect(candidates.count == scene.facts.places.count)
        for candidate in candidates {
            let id = try #require(candidate["id"]?.stringValue)
            let place = try #require(scene.facts.places[id])
            let leg = Travel.leg(from: station.location.coordinate, to: place.location.coordinate,
                                 walkTimes: StraightLineWalkTimes())
            #expect(candidate["fromBase"] == .object(["mode": .string(leg.mode.rawValue),
                                                      "minutes": .integer(leg.minutes)]))
        }

        // The planner asks about accommodation: the check flags it and the plan goes to repair.
        let badPlan = PlanDraft(days: scene.plan.days, lists: scene.plan.lists, skippedMeals: scene.plan.skippedMeals,
                                openQuestions: ["Do you need accommodation for the night?"], changes: [])
        let script = StayScript([research, try json(badPlan), try json(scene.plan)])
        let (_, draft) = try await researchAndPlan(scene, script: script)
        let issues = await planIssues(script.events, round: 0)
        #expect(issues.contains { $0.kind == .stayContradiction && $0.severity == .error })
        #expect(await script.requests.count == 3)

        // The arrival and departure the traveller gave are fixed stops, as bookings are.
        let stops = draft.days[0].stops
        #expect(stops.contains { $0.id == "taba-transit-arrival" && $0.placeId == "manual:arrival"
            && $0.start == LocalTime("11:00") && $0.reason == "Arrival the traveller gave" })
        #expect(stops.contains { $0.id == "taba-transit-departure" && $0.placeId == "manual:arrival"
            && $0.start == LocalTime("17:00") && $0.reason == "Departure the traveller gave" })
    }

    /// A place filed in a list it does not fit is dropped by code, with no repair round, and skipped meals are not
    /// turned into questions for the traveller.
    @Test func misfiledListPlacesAreDroppedAndSkippedMealsAreNotQuestions() async throws {
        let scene = try scenario(days: 1, base: .arrival)
        let lists = scene.plan.lists.map { list in
            list.key == .eat ? DraftList(key: .eat, placeIds: list.placeIds + ["osm:node/3"]) : list
        }
        let date = scene.plan.days[0].date
        let misfiled = PlanDraft(days: scene.plan.days, lists: lists,
                                 skippedMeals: [SkippedMeal(date: date, slot: .breakfast, reason: "Arrives at 11:00")],
                                 openQuestions: [], changes: [])
        let script = StayScript([research, try json(misfiled)])
        let (_, draft) = try await researchAndPlan(scene, script: script)
        #expect(await script.requests.count == 2)
        #expect(draft.lists.first { $0.key == .eat }?.placeIds == ["osm:node/1"])
        #expect(draft.openQuestions.isEmpty)
        #expect(draft.skippedMeals.count == 1)
    }

    @Test func writerMentioningAHotelOnATripWithNoStayIsRejectedTwice() async throws {
        let scene = try scenario(days: 1, base: .arrival)
        let bad = withBody(scene.copy, stop: "d1-lunch", body: "Leave your bags at the hotel before lunch.")
        let script = StayScript([research, try json(scene.plan), try json(bad), try json(bad)])
        let (researched, draft) = try await researchAndPlan(scene, script: script)
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().copyStage(id: "test", model: "fake", researched: researched, draft: draft,
                                         weather: [], send: { try await script.send($0) },
                                         evidence: { await script.record($0) })
        }
        #expect(await script.requests.count == 4)
        let flagged = await copyIssues(script.events).filter { isStayContradiction($0.kind) }
        #expect(flagged.count >= 2)
    }

    @Test func aCleanRunOfTheLeedsTripCompletesWithStationAsBase() async throws {
        let scene = try scenario(days: 1, base: .arrival)
        let script = StayScript([research, try json(scene.plan), try json(scene.copy)])
        let guide = try await GuidePipeline().run(
            id: "test", model: "fake", facts: scene.facts, measurements: scene.measurements, weather: [],
            stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(guide.contradictions.isEmpty)
        #expect(guide.stayArrangement == .notNeeded)
        #expect(guide.base?.place.id == "manual:arrival")
        #expect(guide.base?.phrase == "the station")
        #expect(guide.lists.flatMap(\.placeIds).allSatisfy { guide.places[$0] != nil })
        #expect(guide.days.flatMap(\.stops).contains { $0.placeId == "manual:arrival" })
    }

    @Test func overnightTripWithABookedStayCanCheckIn() async throws {
        let scene = try scenario(days: 2, base: .stay)
        let checkIn = withBody(scene.copy, stop: "d1-lunch", body: "Check in at your stay before you walk out.")
        let script = StayScript([research, try json(scene.plan), try json(checkIn)])
        let guide = try await GuidePipeline().run(
            id: "test", model: "fake", facts: scene.facts, measurements: scene.measurements, weather: [],
            stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(guide.stayArrangement == .booked)
        #expect(guide.base?.kind == .stay)
        #expect(guide.base?.place.id == "manual:stay")
        #expect(guide.days.first?.stops.contains {
            $0.copy.body == "Check in at your stay before you walk out."
        } == true)
        #expect(guide.contradictions.isEmpty)
        #expect(await !copyIssues(script.events).contains { isStayContradiction($0.kind) })
    }

    @Test func multiDayTripWithNoStayHasNoBaseAndNoWalks() async throws {
        let scene = try scenario(days: 2, base: .none)
        let scaffold = Guide(id: "test", version: 1, status: .draft, trip: scene.facts.trip, bookings: [],
                             stay: scene.facts.stay, places: scene.facts.places, days: [], lists: [], tasting: [],
                             practical: [], sources: [])
        let input = try PipelineInputBuilder.plan(guide: scaffold, measurements: scene.measurements, weather: [],
                                                  findings: [], requests: .object([:]))
        let anchors = try #require(input.objectValue?["anchors"]?.objectValue)
        #expect(anchors["base"] == .null)
        #expect(anchors["stay"]?.objectValue?["arrangement"] == .string("unknown"))
        let candidates = try #require(input.objectValue?["candidates"]?.arrayValue).compactMap(\.objectValue)
        #expect(candidates.allSatisfy { $0["fromBase"] == .null })

        let hotel = withBody(scene.copy, stop: "d1-lunch", body: "Your hotel is ready when you are.")
        let script = StayScript([research, try json(scene.plan), try json(hotel), try json(hotel)])
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().run(
                id: "test", model: "fake", facts: scene.facts, measurements: scene.measurements, weather: [],
                stayArea: "Centre", send: { try await script.send($0) }, evidence: { await script.record($0) })
        }
    }

    @Test func sameDayTripWithAStayCannotCheckIn() async throws {
        let scene = try scenario(days: 1, base: .stay)
        #expect(scene.facts.stay.arrangement == .booked)
        #expect(scene.facts.stay.checkIn == nil && scene.facts.stay.timesEstimated == nil)
        let checkIn = withBody(scene.copy, stop: "d1-lunch", body: "Check-in at the hotel comes first.")
        let script = StayScript([research, try json(scene.plan), try json(checkIn), try json(checkIn)])
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().run(
                id: "test", model: "fake", facts: scene.facts, measurements: scene.measurements, weather: [],
                stayArea: "Centre", send: { try await script.send($0) }, evidence: { await script.record($0) })
        }
    }

    /// Each of the four trips, with clean copy, completes with no contradictions, a base that matches the plan input,
    /// and only known places in its lists.
    @Test func everyTripShapeCompletesConsistently() async throws {
        let shapes: [(days: Int, base: BaseKind)] = [(1, .arrival), (2, .stay), (2, .none), (1, .stay)]
        for shape in shapes {
            let scene = try scenario(days: shape.days, base: shape.base)
            let script = StayScript([research, try json(scene.plan), try json(scene.copy)])
            let guide = try await GuidePipeline().run(
                id: "test", model: "fake", facts: scene.facts, measurements: scene.measurements, weather: [],
                stayArea: "Centre", send: { try await script.send($0) }, evidence: { await script.record($0) })
            #expect(guide.contradictions.isEmpty)
            let scaffold = Guide(id: "test", version: 1, status: .draft, trip: scene.facts.trip, bookings: [],
                                 stay: scene.facts.stay, places: scene.facts.places, days: [], lists: [], tasting: [],
                                 practical: [], sources: [])
            let input = try PipelineInputBuilder.plan(guide: scaffold, measurements: scene.measurements, weather: [],
                                                      findings: [], requests: .object([:]))
            let anchorBase = input.objectValue?["anchors"]?.objectValue?["base"]?.objectValue?["placeId"]
            #expect(guide.base?.place.id == anchorBase?.stringValue)
            #expect(guide.lists.flatMap(\.placeIds).allSatisfy { guide.places[$0] != nil })
            #expect(guide.stayArrangement == scene.facts.stayArrangement)
        }
    }
}

/// The arrival and departure stops the pipeline adds for the times the traveller gave. The writer writes them too.
private func transitStops(_ facts: TripFacts) -> [String] {
    var ids: [String] = []
    if facts.trip.travel?.arrivalPlaceId != nil, facts.trip.dates.arrives != nil { ids.append("taba-transit-arrival") }
    if facts.trip.travel?.departurePlaceId != nil, facts.trip.dates.leaves != nil {
        ids.append("taba-transit-departure")
    }
    return ids
}
