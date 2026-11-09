// swiftlint:disable file_length
import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import SourcesKit
import Testing

private actor PipelineScript {
    var replies: [String]
    var requests: [ResponsesRequest] = []
    var events: [PipelineEvidence] = []
    let sourceURLs: [String]
    init(_ replies: [String], sourceURLs: [String] = []) {
        self.replies = replies
        self.sourceURLs = sourceURLs
    }
    func send(_ request: ResponsesRequest) throws -> ResponsesResult {
        requests.append(request)
        guard !replies.isEmpty else { throw ScriptError.exhausted }
        return ResponsesResult(text: replies.removeFirst(), status: "completed", responseId: nil, usage: nil,
                               webSearchCount: 0, sourceURLs: sourceURLs, citationURLs: [])
    }
    func record(_ event: PipelineEvidence) { events.append(event) }
    enum ScriptError: Error { case exhausted }
}

struct GuidePipelineTests {
    private struct Fixture {
        let facts: TripFacts
        let measurements: PipelineInputMeasurements
        let draft: PlanDraft
        let copy: GuideCopy
    }
    private func data() throws -> Fixture {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: directory
            .deletingLastPathComponent()
            .appendingPathComponent("GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")))
        let day = guide.trip.dates.start
        let trip = Trip(destination: guide.trip.destination, dates: TripDates(start: day, end: day),
                        party: guide.trip.party, budget: guide.trip.budget, interests: guide.trip.interests,
                        pace: guide.trip.pace, voice: guide.trip.voice)
        let facts = TripFacts(trip: trip, bookings: [], stay: guide.stay, places: guide.places,
                              practical: guide.practical, sources: guide.sources)
        let areas = Dictionary(uniqueKeysWithValues: facts.places.keys.map { ($0, "area") })
        let walks = Dictionary(uniqueKeysWithValues: facts.places.keys.map { ($0, 1) })
        let measurements = PipelineInputMeasurements(areas: areas, walkFromStay: walks,
            areaWalkMinutes: .object([:]), arrivalWalkMinutes: 0, departureWalkMinutes: 0)
        let place = try #require(facts.places.values.first { $0.kind.needsCopy })
        let stop = PlanDraftStop(id: "original-stop", placeId: nil, kind: .meal, mealSlot: .breakfast,
                                 start: try #require(LocalTime("09:00")), minutes: 30, flexible: false,
                                 alternative: nil, reason: "Rest", findingIds: [])
        let draft = PlanDraft(days: [.init(date: day, theme: "Walk", stops: [stop])],
                              lists: [.init(key: .eat, placeIds: [place.id]), .init(key: .drink, placeIds: []),
                                      .init(key: .photos, placeIds: [])], skippedMeals: [],
                              openQuestions: [], changes: [])
        let copy = GuideCopy(hero: .init(title: "City walks", subtitle: "A gentle wander.", tagline: "Take it easy"),
            days: [.init(date: day, title: "Walk", summary: "Enjoy the day.")],
            stops: [.init(id: stop.id, title: "Rest", body: "Take a break.", actionLabel: nil)],
            places: [.init(id: place.id, tag: "Local", blurb: "Enjoy a visit.")],
            lists: [.init(key: .eat, title: "Food", caption: "Find a meal."),
                    .init(key: .drink, title: "Drinks", caption: "Find a drink."),
                    .init(key: .photos, title: "Views", caption: "Find a view.")],
            tasting: Array(repeating: TasteItem(name: "Oats", note: "A warming dish."), count: 6),
            notes: .init(weather: "Bring a layer.", light: "Enjoy the light.",
                         backupPlan: "Take shelter.", rules: "Take your time."))
        return Fixture(facts: facts, measurements: measurements, draft: draft, copy: copy)
    }
    private func json<T: Encodable>(_ value: T) throws -> String {
        try #require(String(data: JSONEncoder().encode(value), encoding: .utf8))
    }
    private var research: String { #"{"findings":[],"suggestedPlaces":[],"searchNotes":"none"}"# }

    @Test func stagesResumeFromResearchCheckpoint() async throws {
        let fixture = try data()
        let script = try PipelineScript([research, json(fixture.draft), json(fixture.draft),
                                         json(fixture.draft), json(fixture.copy)])
        let pipeline = GuidePipeline()
        let original = fixture.measurements
        let measurements = PipelineInputMeasurements(
            areas: original.areas, areaLabels: original.areas.mapValues { _ in "Named area" },
            walkFromStay: original.walkFromStay, areaWalkMinutes: original.areaWalkMinutes,
            alwaysOpenPlaceIDs: [fixture.facts.stay.placeId], arrivalWalkMinutes: 2, departureWalkMinutes: 3,
            arrivalMarginMinutes: 4, departureMarginMinutes: 5)
        let researched = try await pipeline.researchStage(
            model: "fake", facts: fixture.facts, measurements: measurements, stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        let factsCheckpoint = try JSONDecoder().decode(
            FactsCheckpoint.self, from: JSONEncoder().encode(FactsCheckpoint(fixture.facts)))
        let measurementsCheckpoint = try JSONDecoder().decode(
            MeasurementsCheckpoint.self, from: JSONEncoder().encode(MeasurementsCheckpoint(measurements)))
        #expect(factsCheckpoint.value == fixture.facts)
        #expect(measurementsCheckpoint.value.areaLabels == measurements.areaLabels)
        #expect(measurementsCheckpoint.value.departureMarginMinutes == 5)
        let bytes = try JSONEncoder().encode(researched)
        let restored = try JSONDecoder().decode(ResearchedPipeline.self, from: bytes)
        #expect(restored.facts == fixture.facts)
        #expect(restored.measurements.areaLabels == measurements.areaLabels)
        #expect(restored.measurements.areas == measurements.areas)
        #expect(restored.measurements.alwaysOpenPlaceIDs == measurements.alwaysOpenPlaceIDs)
        #expect(restored.measurements.arrivalWalkMinutes == 2)
        #expect(restored.measurements.departureWalkMinutes == 3)
        #expect(restored.measurements.arrivalMarginMinutes == 4)
        #expect(restored.measurements.departureMarginMinutes == 5)
        let draft = try await pipeline.planStage(id: "test", model: "fake", researched: restored, weather: [],
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        let restoredDraft = try JSONDecoder().decode(PlanDraft.self, from: JSONEncoder().encode(draft))
        let guide = try await pipeline.writeStage(id: "test", model: "fake", researched: restored,
            draft: restoredDraft, weather: [], send: { try await script.send($0) },
            evidence: { await script.record($0) })
        try guide.validateStructure()
        #expect(await script.requests.count == 5)
    }

    @Test func resumesPlanAndCopyWithoutRepeatingInitialRequest() async throws {
        let fixture = try data()
        let invalid = PlanDraft(days: [], lists: fixture.draft.lists, skippedMeals: [],
                                openQuestions: [], changes: [])
        let initial = try json(invalid)
        let script = try PipelineScript([research, initial, json(fixture.draft), json(fixture.draft),
                                         json(fixture.copy)])
        let pipeline = GuidePipeline()
        let researched = try await pipeline.researchStage(
            model: "fake", facts: fixture.facts, measurements: fixture.measurements, stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        let planned = try await pipeline.initialPlanStage(
            id: "test", model: "fake", researched: researched, weather: [],
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(await script.requests.count == 2)
        #expect(!(await script.events.contains { if case .plan = $0 { true } else { false } }))
        let restored = try JSONDecoder().decode(PlannedPipeline.self, from: JSONEncoder().encode(planned))
        let draft = try await pipeline.checkStage(
            id: "test", model: "fake", researched: researched, planned: restored,
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        let requests = await script.requests
        #expect(requests.map(\.messages.count) == [1, 1, 3, 5])
        #expect(requests[2].messages[1].content == initial)
        #expect(requests[2].messages[2].content.contains("Missing day"))
        #expect(draft.days[0].stops[0].id == "original-stop")
        let copy = try await pipeline.copyStage(
            id: "test", model: "fake", researched: researched, draft: draft, weather: [],
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(!(await script.events.contains { if case .completed = $0 { true } else { false } }))
        let restoredCopy = try JSONDecoder().decode(GuideCopy.self, from: JSONEncoder().encode(copy))
        let guide = try await pipeline.assembleStage(id: "test", researched: researched, draft: draft,
                                                     copy: restoredCopy, evidence: { await script.record($0) })
        try guide.validateStructure()
        #expect(await script.requests.count == 5)
        #expect(await script.events.contains { if case .completed = $0 { true } else { false } })
    }

    @Test func completesWithDecodeAndCopyRetries() async throws {
        let fixture = try data()
        let (facts, measurements) = (fixture.facts, fixture.measurements)
        let (draft, copy) = (fixture.draft, fixture.copy)
        let badCopy = GuideCopy(hero: .init(title: "Alone", subtitle: "A walk.", tagline: "Rest"),
                                days: copy.days, stops: copy.stops, places: copy.places, lists: copy.lists,
                                tasting: copy.tasting, notes: copy.notes)
        let script = try PipelineScript(["not json", research, json(draft), json(draft), json(draft),
                                         json(badCopy), json(copy)])
        let guide = try await GuidePipeline().run(id: "test", model: "fake", facts: facts,
            measurements: measurements, weather: [], stayArea: "Centre", send: { try await script.send($0) },
            evidence: { await script.record($0) })
        try guide.validateStructure()
        #expect(guide.days.first?.stops.first?.copy.title == "Rest")
        let requests = await script.requests
        #expect(requests.count == 7)
        #expect(requests[0].webSearch)
        #expect(requests.last?.messages.count == 3)
        let events = await script.events
        #expect(events.contains { if case .decodeFailed = $0 { true } else { false } })
        #expect(events.contains { if case .completed = $0 { true } else { false } })
    }

    @Test func repairCanProduceUsableGuide() async throws {
        let fixture = try data()
        let invalid = PlanDraft(days: [], lists: fixture.draft.lists, skippedMeals: [],
                                openQuestions: [], changes: [])
        let script = try PipelineScript([research, json(invalid), json(fixture.draft), json(fixture.draft),
                                         json(fixture.copy)])
        let guide = try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
            measurements: fixture.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        try guide.validateStructure()
        let requests = await script.requests
        #expect(requests.map(\.messages.count) == [1, 1, 3, 5, 1])
        let previous = try JSONDecoder().decode(PlanDraft.self, from: Data(requests[2].messages[1].content.utf8))
        #expect(previous == invalid)
        #expect(requests[2].messages[2].content.contains("Missing day"))
    }

    @Test func unresolvedBoundaryBookingFailsBeforeAnyAICall() async throws {
        let fixture = try data()
        let day = fixture.facts.trip.dates.end
        let booking = Booking(id: "out", kind: .train, from: "Waverley Station", fromPlaceId: nil,
                              to: "Elsewhere", toPlaceId: nil,
                              departs: LocalDateTime(date: day, time: try #require(LocalTime("14:30"))),
                              arrives: LocalDateTime(date: day, time: try #require(LocalTime("18:00"))), notes: nil)
        let facts = TripFacts(trip: fixture.facts.trip, bookings: [booking], stay: fixture.facts.stay,
                              places: fixture.facts.places, practical: fixture.facts.practical,
                              sources: fixture.facts.sources)
        let script = PipelineScript([])
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().run(id: "test", model: "fake", facts: facts,
                measurements: fixture.measurements, weather: [], stayArea: "Centre",
                send: { try await script.send($0) }, evidence: { await script.record($0) })
        }
        #expect(await script.requests.isEmpty)
    }

    @Test func insertsBookedTransitIntoWriterPlan() async throws {
        let fixture = try data()
        let day = fixture.facts.trip.dates.start
        let previous = try #require(day.adding(days: -1))
        let next = try #require(day.adding(days: 1))
        func moment(_ date: LocalDate, _ time: String) throws -> LocalDateTime {
            LocalDateTime(date: date, time: try #require(LocalTime(time)))
        }
        let bookings = try [
            Booking(id: "in", kind: .train, from: "Elsewhere", fromPlaceId: nil,
                    to: fixture.facts.trip.destination.name, toPlaceId: nil,
                    departs: moment(previous, "23:00"), arrives: moment(day, "08:00"), notes: nil),
            Booking(id: "out", kind: .train, from: fixture.facts.trip.destination.name, fromPlaceId: nil,
                    to: "Elsewhere", toPlaceId: nil, departs: moment(day, "20:00"),
                    arrives: moment(next, "01:00"), notes: nil)
        ]
        let facts = TripFacts(trip: fixture.facts.trip, bookings: bookings, stay: fixture.facts.stay,
                              places: fixture.facts.places, practical: fixture.facts.practical,
                              sources: fixture.facts.sources)
        let travelCopy = ["taba-transit-arrival", "taba-transit-departure"].map {
            GuideCopyStop(id: $0, title: "Travel", body: "Take the train.", actionLabel: nil)
        }
        let base = fixture.copy
        let copy = GuideCopy(hero: base.hero, days: base.days, stops: base.stops + travelCopy,
                             places: base.places, lists: base.lists, tasting: base.tasting, notes: base.notes)
        let script = try PipelineScript([research, json(fixture.draft), json(fixture.draft), json(fixture.draft),
                                         json(copy)])
        let guide = try await GuidePipeline().run(id: "test", model: "fake", facts: facts,
            measurements: fixture.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(guide.days[0].stops.map(\.kind) == [.travel, .meal, .travel])
        let requests = await script.requests
        #expect(requests[4].userText.contains("taba-transit-arrival"))
        #expect(requests[4].userText.contains("taba-transit-departure"))
    }

}

extension GuidePipelineTests {
    private func transitBookings(_ trip: Trip, dates: [LocalDate]) throws -> [Booking] {
        func moment(_ date: LocalDate, _ time: String) throws -> LocalDateTime {
            LocalDateTime(date: date, time: try #require(LocalTime(time)))
        }
        return try [
            Booking(id: "in", kind: .train, from: "Elsewhere", fromPlaceId: nil,
                    to: trip.destination.name, toPlaceId: nil,
                    departs: moment(try #require(dates[0].adding(days: -1)), "23:00"),
                    arrives: moment(dates[0], "08:00"), notes: nil),
            Booking(id: "out", kind: .train, from: trip.destination.name, fromPlaceId: nil,
                    to: "Elsewhere", toPlaceId: nil, departs: moment(dates[2], "22:00"),
                    arrives: moment(try #require(dates[2].adding(days: 1)), "01:00"), notes: nil)
        ]
    }

    @Test func multiDayMealsAndTransitReachFinalGuide() async throws {
        let fixture = try data()
        let first = fixture.facts.trip.dates.start
        let dates = try (0...2).map { try #require(first.adding(days: $0)) }
        let original = fixture.facts.trip
        let trip = Trip(destination: original.destination, dates: TripDates(start: dates[0], end: dates[2]),
                        party: original.party, budget: original.budget, interests: original.interests,
                        pace: original.pace, voice: original.voice)
        let bookings = try transitBookings(trip, dates: dates)
        let facts = TripFacts(trip: trip, bookings: bookings, stay: fixture.facts.stay,
                              places: fixture.facts.places, practical: fixture.facts.practical,
                              sources: fixture.facts.sources)
        let days = try dates.enumerated().map { index, date in
            var stops = try [(MealSlot.breakfast, "09:00"), (.lunch, "12:00"), (.dinner, "18:00")].map { slot, time in
                PlanDraftStop(id: "day\(index)-\(slot.rawValue)", placeId: nil, kind: .meal, mealSlot: slot,
                              start: try #require(LocalTime(time)), minutes: 45, flexible: false,
                              alternative: nil, reason: "Meal", findingIds: [])
            }
            stops.insert(PlanDraftStop(id: "day\(index)-sight", placeId: "manual:royal-mile", kind: .sight,
                                       mealSlot: nil, start: try #require(LocalTime("10:15")), minutes: 45,
                                       flexible: false, alternative: nil, reason: "Walk", findingIds: []), at: 1)
            return PlanDraftDay(date: date, theme: "Walk", stops: stops)
        }
        let draft = PlanDraft(days: days, lists: fixture.draft.lists, skippedMeals: [], openQuestions: [], changes: [])
        let stopIDs = days.flatMap(\.stops).map(\.id) + ["taba-transit-arrival", "taba-transit-departure"]
        var placeCopy = fixture.copy.places
        if !placeCopy.contains(where: { $0.id == "manual:royal-mile" }) {
            placeCopy.append(.init(id: "manual:royal-mile", tag: "Walk", blurb: "Explore the street."))
        }
        let copy = GuideCopy(hero: fixture.copy.hero,
            days: dates.map { .init(date: $0, title: "Walk", summary: "Enjoy the day.") },
            stops: stopIDs.map { .init(id: $0, title: "Stop", body: "Enjoy the day.", actionLabel: nil) },
            places: placeCopy, lists: fixture.copy.lists, tasting: fixture.copy.tasting,
            notes: fixture.copy.notes)
        let script = try PipelineScript([research, json(draft), json(draft), json(draft), json(copy)])
        let guide = try await GuidePipeline().run(id: "test", model: "fake", facts: facts,
            measurements: fixture.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(guide.days.count == 3)
        #expect(guide.days.flatMap(\.stops).filter { $0.kind == .meal }.count == 9)
        #expect(guide.days.flatMap(\.stops).filter { $0.kind == .travel }.count == 2)
        #expect(!PlanChecker().check(guide).contains { $0.severity == .error })
    }

    @Test func sourcedResearchSurvivesInGuideAndWriterInput() async throws {
        let fixture = try data()
        let finding = ResearchFinding(id: "f1", kind: .event, title: "Market", summary: "A local market.",
            startDate: nil, endDate: nil, times: nil, placeName: nil, address: nil,
            url: "https://example.com/market", sourceTitle: "Market page", confidence: .high, onTripDates: true)
        let research = ResearchResult(findings: [finding], suggestedPlaces: [], searchNotes: "")
        let script = try PipelineScript([json(research), json(fixture.draft), json(fixture.draft),
                                         json(fixture.draft), json(fixture.copy)],
                                        sourceURLs: [finding.url])
        let guide = try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
            measurements: fixture.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        let source = try #require(guide.sources.first { $0.url == finding.url })
        #expect(guide.practical.contains { $0.sourceId == source.id && $0.text.contains(finding.summary) })
        #expect(await script.requests.last?.userText.contains(finding.url) == true)
    }

    @Test func invalidFindingAndMealFieldsAreSentToRepair() async throws {
        let fixture = try data()
        let day = fixture.draft.days[0]
        let stop = day.stops[0]
        let bad = PlanDraftStop(id: stop.id, placeId: nil, kind: .meal, mealSlot: nil, start: stop.start,
                                minutes: stop.minutes, flexible: false, alternative: nil, reason: "Meal",
                                findingIds: ["unknown"])
        let invalid = PlanDraft(days: [.init(date: day.date, theme: day.theme, stops: [bad])],
                                lists: fixture.draft.lists, skippedMeals: [], openQuestions: [], changes: [])
        let script = try PipelineScript([research, json(invalid), json(fixture.draft), json(fixture.draft),
                                         json(fixture.copy)])
        _ = try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
            measurements: fixture.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        let feedback = await script.requests[2].messages[2].content
        #expect(feedback.contains("Invalid meal slot"))
        #expect(feedback.contains("Unknown finding"))
    }

    @Test func preparedResearchCandidateCanBePlanned() async throws {
        let fixture = try data()
        let id = try #require(fixture.draft.lists.first?.placeIds.first)
        let place = try #require(fixture.facts.places[id])
        var remaining = fixture.facts.places
        remaining.removeValue(forKey: id)
        let facts = TripFacts(trip: fixture.facts.trip, bookings: fixture.facts.bookings, stay: fixture.facts.stay,
                              places: remaining, practical: fixture.facts.practical, sources: fixture.facts.sources)
        let suggestion = SuggestedPlace(name: place.name, area: "Centre", kind: place.kind, why: "Worth visiting")
        let research = ResearchResult(findings: [], suggestedPlaces: [suggestion], searchNotes: "")
        let script = try PipelineScript([json(research), json(fixture.draft), json(fixture.draft),
                                         json(fixture.draft), json(fixture.copy)])
        let guide = try await GuidePipeline().run(id: "test", model: "fake", facts: facts,
            measurements: fixture.measurements, weather: [], stayArea: "Centre",
            resolveSuggestion: { _ in place }, prepareCandidates: { verified, facts, measurements in
                var places = facts.places
                for item in verified.places { places[item.id] = item }
                return (TripFacts(trip: facts.trip, bookings: facts.bookings, stay: facts.stay,
                                  places: places, practical: facts.practical, sources: facts.sources), measurements)
            }, send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(guide.places[id] != nil)
        #expect(await script.events.contains {
            if case let .research(_, ids) = $0 { ids.contains(id) } else { false }
        })
    }

    @Test func transportFailureIsNotRetried() async throws {
        let fixture = try data()
        let script = PipelineScript([])
        await #expect(throws: PipelineScript.ScriptError.self) {
            try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
                measurements: fixture.measurements, weather: [], stayArea: "Centre",
                send: { try await script.send($0) }, evidence: { await script.record($0) })
        }
        #expect(await script.requests.count == 1)
        #expect(await script.events.contains { if case .requestFailed = $0 { true } else { false } })
    }

    @Test func cancellationStopsBeforeTransport() async throws {
        let fixture = try data()
        let script = PipelineScript([])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
                measurements: fixture.measurements, weather: [], stayArea: "Centre",
                send: { try await script.send($0) }, evidence: { await script.record($0) })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await script.requests.isEmpty)
    }

    @Test func decodeRetryIsBounded() async throws {
        let fixture = try data()
        let script = PipelineScript(["bad", "bad", research])
        await #expect(throws: (any Error).self) {
            try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
                measurements: fixture.measurements, weather: [], stayArea: "Centre",
                send: { try await script.send($0) }, evidence: { await script.record($0) })
        }
        #expect(await script.requests.count == 2)
    }

    @Test func researchDeduplicatesResolvedPlaceIDs() async throws {
        let fixture = try data()
        let place = try #require(fixture.facts.places.values.first)
        let suggestion = SuggestedPlace(name: place.name, area: "Centre", kind: place.kind, why: "Visit")
        let research = ResearchResult(findings: [], suggestedPlaces: [suggestion, suggestion], searchNotes: "")
        let verified = try await ResearchVerification.verify(research, sourceURLs: [], resolve: { _ in place })
        #expect(verified.places.map(\.id) == [place.id])
        #expect(verified.result.suggestedPlaces.count == 1)
    }

    @Test func informationalIssuesDoNotTriggerRepair() async throws {
        let fixture = try data()
        let place = try #require(fixture.facts.places.values.first {
            !$0.hours.hoursKnown && $0.kind.needsCopy && $0.indoor
                && ![.lodging, .station, .luggage].contains($0.kind)
        })
        let day = fixture.draft.days[0].date
        let stops = try [("breakfast", "09:00", MealSlot.breakfast), ("lunch", "12:00", .lunch),
                         ("dinner", "18:00", .dinner)].map { id, time, slot in
            PlanDraftStop(id: id, placeId: nil, kind: .meal, mealSlot: slot,
                          start: try #require(LocalTime(time)), minutes: 30, flexible: false,
                          alternative: nil, reason: "Meal", findingIds: [])
        } + [PlanDraftStop(id: "sight", placeId: place.id, kind: .sight, mealSlot: nil,
                           start: try #require(LocalTime("10:00")), minutes: 30, flexible: true,
                           alternative: nil, reason: "Check hours", findingIds: [])]
        let draft = PlanDraft(days: [.init(date: day, theme: "Walk", stops: stops)],
            lists: fixture.draft.lists, skippedMeals: [], openQuestions: [], changes: [])
        let existing = fixture.copy.places
        let places = existing.contains { $0.id == place.id } ? existing
            : existing + [.init(id: place.id, tag: "Local", blurb: "Enjoy a visit.")]
        let copy = GuideCopy(hero: fixture.copy.hero, days: fixture.copy.days,
            stops: stops.map { GuideCopyStop(id: $0.id, title: "Stop", body: "Enjoy the day.", actionLabel: nil) },
            places: places, lists: fixture.copy.lists, tasting: fixture.copy.tasting, notes: fixture.copy.notes)
        let script = try PipelineScript([research, json(draft), json(copy)])
        _ = try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
            measurements: fixture.measurements, weather: [], stayArea: "Centre",
            send: { try await script.send($0) }, evidence: { await script.record($0) })
        #expect(await script.requests.count == 3)
        #expect(await script.events.contains { event in
            if case let .plan(round, issues) = event {
                return round == 0 && issues.contains { $0.severity == .info }
            }
            return false
        })
    }

    @Test func duplicateStopIDsReachRepairWithoutAssembly() async throws {
        let fixture = try data()
        let day = fixture.draft.days[0]
        let invalid = PlanDraft(days: [.init(date: day.date, theme: day.theme, stops: day.stops + day.stops)],
                                lists: fixture.draft.lists, skippedMeals: [], openQuestions: [], changes: [])
        let script = try PipelineScript([research, json(invalid), json(invalid), json(invalid)])
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().run(id: "test", model: "fake", facts: fixture.facts,
                measurements: fixture.measurements, weather: [], stayArea: "Centre",
                send: { try await script.send($0) }, evidence: { await script.record($0) })
        }
        let requests = await script.requests
        #expect(requests[2].messages[2].content.contains("Duplicate or reserved stop id"))
        #expect(requests.map(\.messages.count) == [1, 1, 3, 5])
        let labels = await script.events.compactMap { event -> String? in
            if case let .request(step, _, _, _) = event { return step }
            return nil
        }
        #expect(labels == ["research", "plan", "repair1", "repair2"])
    }

    @Test func planningWindowIsEnforcedBeforeChecker() async throws {
        let fixture = try data()
        let day = fixture.draft.days[0].date
        let booking = Booking(id: "arrival", kind: .train, from: "Elsewhere", fromPlaceId: nil,
            to: fixture.facts.trip.destination.name, toPlaceId: nil,
            departs: .init(date: day, time: try #require(LocalTime("07:00"))),
            arrives: .init(date: day, time: try #require(LocalTime("08:00"))), notes: nil)
        let facts = TripFacts(trip: fixture.facts.trip, bookings: [booking], stay: fixture.facts.stay,
            places: fixture.facts.places, practical: fixture.facts.practical, sources: fixture.facts.sources)
        let measurements = PipelineInputMeasurements(areas: fixture.measurements.areas,
            walkFromStay: fixture.measurements.walkFromStay, areaWalkMinutes: .object([:]),
            arrivalWalkMinutes: 90, departureWalkMinutes: 0)
        let script = try PipelineScript([research, json(fixture.draft), json(fixture.draft), json(fixture.draft)])
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().run(id: "test", model: "fake", facts: facts, measurements: measurements,
                weather: [], stayArea: "Centre", send: { try await script.send($0) },
                evidence: { await script.record($0) })
        }
        #expect(await script.requests[2].messages[2].content.contains("outside planning window"))
    }

    @Test func ticketMustBeRepresented() async throws {
        let fixture = try data()
        let day = fixture.draft.days[0].date
        let id = try #require(fixture.draft.lists[0].placeIds.first)
        let time = try #require(LocalTime("10:00"))
        let booking = Booking(id: "ticket", kind: .ticket, from: "Venue", fromPlaceId: id,
            to: "Venue", toPlaceId: id, departs: .init(date: day, time: time),
            arrives: .init(date: day, time: time), notes: nil)
        let facts = TripFacts(trip: fixture.facts.trip, bookings: [booking], stay: fixture.facts.stay,
            places: fixture.facts.places, practical: fixture.facts.practical, sources: fixture.facts.sources)
        let script = try PipelineScript([research, json(fixture.draft), json(fixture.draft), json(fixture.draft)])
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().run(id: "test", model: "fake", facts: facts, measurements: fixture.measurements,
                weather: [], stayArea: "Centre", send: { try await script.send($0) },
                evidence: { await script.record($0) })
        }
        #expect(await script.requests[2].messages[2].content.contains("Ticket booking ticket"))
    }

    @Test func stopsAfterTwoRepairsAndKeepsHistory() async throws {
        let fixture = try data()
        let (facts, measurements) = (fixture.facts, fixture.measurements)
        let draft = fixture.draft
        let invalid = PlanDraft(days: [], lists: draft.lists, skippedMeals: [], openQuestions: [], changes: [])
        let script = try PipelineScript([research, json(invalid), json(invalid), json(invalid)])
        await #expect(throws: GuidePipelineError.self) {
            try await GuidePipeline().run(id: "test", model: "fake", facts: facts, measurements: measurements,
                weather: [], stayArea: "Centre", send: { try await script.send($0) },
                evidence: { await script.record($0) })
        }
        let requests = await script.requests
        #expect(requests.map(\.messages.count) == [1, 1, 3, 5])
        let events = await script.events
        #expect(events.contains { if case .failure = $0 { true } else { false } })
        #expect(events.filter { if case .plan = $0 { true } else { false } }.count == 3)
    }
}
