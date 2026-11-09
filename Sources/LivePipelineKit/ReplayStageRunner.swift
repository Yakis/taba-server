import BuildKit
import Foundation
import GuideKit
import PipelineKit
import ResponsesKit
import ServerKit
import SourcesKit

public enum ReplayError: Error, Sendable {
    case incompatibleInput, missingEvent, malformedEvent, exhaustedResponses
}

/// Local-only replay of a recorded run. It never creates a network client.
public struct ReplayStageRunner: Sendable {
    private let events: [[String: JSONValue]]
    private let guide: Guide
    private let model: String

    public init(directory: URL) throws {
        let decoder = JSONDecoder()
        events = try decoder.decode([[String: JSONValue]].self,
                                    from: Data(contentsOf: directory.appendingPathComponent("run.json")))
        guide = try decoder.decode(Guide.self, from: Data(contentsOf: directory.appendingPathComponent("guide.json")))
        guard let value = events.first(where: { $0["event"]?.stringValue == "started" })?["model"]?.stringValue else {
            throw ReplayError.missingEvent
        }
        model = value
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public func run(_ work: BuildWork, evidence: @escaping BuildEvidenceSink) async throws -> StageResult {
        let source = try event("sources")
        guard let seed = work.input.facts, work.input.stay == nil,
              work.input.destination.caseInsensitiveCompare(guide.trip.destination.name) == .orderedSame,
              work.input.from == guide.trip.dates.start, work.input.to == guide.trip.dates.end,
              seed.trip == guide.trip, seed.stay == guide.stay, seed.bookings == guide.bookings else {
            throw ReplayError.incompatibleInput
        }
        let recordedPlaces: [String: Place] = try decode(source, "places")
        guard seed.places.allSatisfy({ recordedPlaces[$0.key] == $0.value }),
              guide.practical.starts(with: seed.practical) else { throw ReplayError.incompatibleInput }
        let pipeline = GuidePipeline()
        let emit: GuidePipeline.EvidenceSink = { await evidence(.pipeline($0)) }
        let responseQueue = ReplayResponses(events: events, stage: work.stage)
        let send: GuidePipeline.Send = { _ in try await responseQueue.next() }
        let id = work.tripID.uuidString
        switch work.stage {
        case .basics:
            let weather = try weather(source)
            let facts = TripFacts(trip: seed.trip, bookings: seed.bookings, stay: seed.stay, places: seed.places,
                                  practical: seed.practical, sources: seed.sources)
            await evidence(.source(["event": .string("replayBasics")]))
            return try result(BasicsCheckpoint(facts: facts, weather: weather, today: work.input.from))
        case .candidates:
            let _: BasicsCheckpoint = try load(.basics, work)
            let facts = TripFacts(trip: try decode(source, "trip"), bookings: try decode(source, "bookings"),
                                  stay: try decode(source, "stay"), places: recordedPlaces,
                                  practical: seed.practical, sources: try decode(source, "sources"))
            let measurement = try measurements(source, fallback: nil, facts: facts)
            let prepared = CandidatesCheckpoint(facts: facts, measurements: measurement,
                weather: try weather(source),
                stayArea: measurement.areaLabels[facts.stay.placeId] ?? work.input.destination)
            await evidence(.source(["event": .string("replayCandidates")]))
            return try result(prepared)
        case .research:
            let candidate: CandidatesCheckpoint = try load(.candidates, work)
            let suggestion = try event("suggestionPreparation")
            let researchEvent = try event("research")
            let accepted: ResearchResult = try decode(researchEvent, "accepted")
            let ids: [String] = try decode(researchEvent, "resolvedPlaceIDs")
            let finalPlaces: [String: Place] = try decode(suggestion, "places")
            guard accepted.suggestedPlaces.count == ids.count else { throw ReplayError.malformedEvent }
            let pairs = Array(zip(accepted.suggestedPlaces, ids))
            let researched = try await pipeline.researchStage(model: model, facts: candidate.facts.value,
                measurements: candidate.measurements.value, stayArea: candidate.stayArea,
                resolveSuggestion: { wanted in
                    guard let pair = pairs.first(where: { $0.0 == wanted }) else { return nil }
                    return finalPlaces[pair.1]
                }, prepareCandidates: { _, facts, old in
                    let updated = TripFacts(trip: facts.trip, bookings: facts.bookings, stay: facts.stay,
                        places: finalPlaces, practical: facts.practical, sources: try decode(suggestion, "sources"))
                    let measured = try measurements(suggestion, fallback: old, facts: updated)
                    await evidence(.source(["event": .string("replaySuggestionPreparation")]))
                    return (updated, measured)
                }, send: send, evidence: emit)
            return try result(researched)
        case .plan:
            let candidate: CandidatesCheckpoint = try load(.candidates, work)
            let researched: ResearchedPipeline = try load(.research, work)
            let requests: JSONValue = .object(["accommodationQuestion": .string(
                "Confirm check-in and check-out times; supplied defaults may be assumptions.")])
            return try await result(pipeline.initialPlanStage(id: id, model: model, researched: researched,
                weather: candidate.weather.map(\.value), requests: requests, send: send, evidence: emit))
        case .check:
            let researched: ResearchedPipeline = try load(.research, work)
            let planned: PlannedPipeline = try load(.plan, work)
            return try await result(pipeline.checkStage(id: id, model: model, researched: researched,
                                                         planned: planned, send: send, evidence: emit))
        case .write:
            let candidate: CandidatesCheckpoint = try load(.candidates, work)
            let researched: ResearchedPipeline = try load(.research, work)
            let draft: PlanDraft = try load(.check, work)
            return try await result(pipeline.copyStage(id: id, model: model, researched: researched, draft: draft,
                weather: candidate.weather.map(\.value), send: send, evidence: emit))
        case .assemble:
            let candidate: CandidatesCheckpoint = try load(.candidates, work)
            let researched: ResearchedPipeline = try load(.research, work)
            let draft: PlanDraft = try load(.check, work)
            let copy: GuideCopy = try load(.write, work)
            let output = try await pipeline.assembleStage(id: id, researched: researched, draft: draft,
                                                           copy: copy, weather: candidate.weather.map(\.value),
                                                           evidence: emit)
            // Replay sends nothing; the guide records the model the saved run was made with.
            let stamped = output.recordingAIModel(model)
            return StageResult(checkpoint: try JSONEncoder().encode(stamped), guide: stamped)
        }
    }

    private func event(_ name: String) throws -> [String: JSONValue] {
        guard let found = events.first(where: { $0["event"]?.stringValue == name }) else {
            throw ReplayError.missingEvent
        }
        return found
    }
}

actor ReplayResponses {
    private var responses: [[String: JSONValue]]
    init(events: [[String: JSONValue]], stage: BuildStage) {
        responses = events.filter { event in
            guard event["event"]?.stringValue == "response", let step = event["step"]?.stringValue else { return false }
            return stage == .check ? step.hasPrefix("repair") : step == stage.rawValue
        }
    }
    func next() throws -> ResponsesResult {
        guard !responses.isEmpty else { throw ReplayError.exhaustedResponses }
        let event = responses.removeFirst()
        guard let text = event["answer"]?.stringValue else { throw ReplayError.malformedEvent }
        let sources: [String] = try decode(event, "sources")
        return ResponsesResult(text: text, status: event["status"]?.stringValue, responseId: nil, usage: nil,
                               webSearchCount: 0, sourceURLs: sources, citationURLs: [])
    }
}

private func decode<T: Decodable>(_ event: [String: JSONValue], _ key: String) throws -> T {
    guard let value = event[key] else { throw ReplayError.malformedEvent }
    do { return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value)) } catch {
        throw ReplayError.malformedEvent
    }
}
private func load<T: Decodable>(_ stage: BuildStage, _ work: BuildWork) throws -> T {
    guard let data = work.checkpoints[stage] else { throw LiveStageError.missingCheckpoint(stage) }
    return try JSONDecoder().decode(T.self, from: data)
}
private func result<T: Encodable>(_ value: T) throws -> StageResult {
    StageResult(checkpoint: try JSONEncoder().encode(value))
}
private func weather(_ event: [String: JSONValue]) throws -> [DayWeather] {
    let days: [[String: JSONValue]] = try decode(event, "weather")
    return try days.map { day in
        DayWeather(date: try decode(day, "date"), rainChance: try decode(day, "rainChance"),
                   tempMax: try decode(day, "tempMax"), tempMin: try decode(day, "tempMin"),
                   summary: try decode(day, "summary"), isForecast: try decode(day, "forecast"))
    }
}
private func measurements(_ event: [String: JSONValue], fallback: PipelineInputMeasurements?, facts: TripFacts) throws
    -> PipelineInputMeasurements {
    let areas: [String: String] = try decode(event, "areas")
    let labels: [String: String]
    if let fallback {
        var names: [String: String] = [:]
        for (place, area) in fallback.areas { names[area] = fallback.areaLabels[place] }
        labels = areas.mapValues { names[$0] ?? $0 }
    } else { labels = try decode(event, "areaLabels") }
    let walker = StraightLineWalkTimes()
    func maximum(_ anchors: [Place]) -> Int {
        anchors.flatMap { anchor in facts.places.values.map {
            walker.minutes(from: anchor.location.coordinate, to: $0.location.coordinate)
        } }.max() ?? 0
    }
    let arrivals = facts.bookings.filter { $0.arrives.date == facts.trip.dates.start }
        .compactMap { $0.toPlaceId.flatMap { facts.places[$0] } }
    let departures = facts.bookings.filter { $0.departs.date == facts.trip.dates.end }
        .compactMap { $0.fromPlaceId.flatMap { facts.places[$0] } }
    return PipelineInputMeasurements(areas: areas, areaLabels: labels, walkFromStay: try decode(event, "stayWalks"),
        areaWalkMinutes: try decode(event, "areaWalks"), alwaysOpenPlaceIDs: [],
        arrivalWalkMinutes: fallback == nil ? try decode(event, "arrivalWalkMinutes") : maximum(arrivals),
        departureWalkMinutes: fallback == nil ? try decode(event, "departureWalkMinutes") : maximum(departures),
        arrivalMarginMinutes: try fallback?.arrivalMarginMinutes ?? decode(event, "arrivalMarginMinutes"),
        departureMarginMinutes: try fallback?.departureMarginMinutes ?? decode(event, "departureMarginMinutes"))
}
