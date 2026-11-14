// swiftlint:disable file_length
import Foundation
import GuideKit
import ResponsesKit
import SourcesKit
/// Evidence is emitted as work happens, including on failure. The sink must persist it if desired.
public enum PipelineEvidence: Sendable {
    case request(step: String, promptID: String, version: Int, request: ResponsesRequest)
    case response(step: String, result: ResponsesResult, seconds: Double)
    case requestFailed(step: String, message: String, seconds: Double)
    case decodeFailed(step: String, message: String)
    case research(accepted: ResearchResult, resolvedPlaceIDs: [String])
    case plan(round: Int, issues: [PlanIssue])
    case copy(issues: [CopyCheckIssue])
    case failure(message: String)
    case completed
}
public enum GuidePipelineError: Error, Sendable {
    case invalidResponseStatus(String)
    case invalidPlan(String)
    case planErrors([PlanIssue])
    case copyErrors([CopyCheckIssue])
    case assemblyProblems([AssemblyProblem])
    /// The finished guide's words contradict its facts, such as a hotel on a trip with no stay.
    case contradictions([GuideContradiction])
}
/// The inputs accepted after research and candidate preparation.
public struct ResearchedPipeline: Sendable {
    public let facts: TripFacts
    public let measurements: PipelineInputMeasurements
    public let verified: VerifiedResearch
}

/// Offline orchestration. Transport, persistence and source preparation are supplied by the caller.
public struct GuidePipeline: Sendable {
    public typealias Send = @Sendable (ResponsesRequest) async throws -> ResponsesResult
    public typealias EvidenceSink = @Sendable (PipelineEvidence) async -> Void
    public typealias SuggestionResolver = @Sendable (SuggestedPlace) async throws -> Place?
    public typealias CandidatePreparer = @Sendable (
        VerifiedResearch, TripFacts, PipelineInputMeasurements
    ) async throws -> (TripFacts, PipelineInputMeasurements)

    public let walkTimes: any WalkTimes
    public init(walkTimes: any WalkTimes = StraightLineWalkTimes()) { self.walkTimes = walkTimes }

    /// The optional preparer admits and measures resolved suggestions before planning.
    public func run( // swiftlint:disable:this function_parameter_count
        id: String, model: String, facts: TripFacts, measurements: PipelineInputMeasurements,
        weather: [DayWeather], stayArea: String, locale: String = "en-GB",
        requests: JSONValue = .object([:]), resolveSuggestion: SuggestionResolver? = nil,
        prepareCandidates: CandidatePreparer? = nil, send: @escaping Send, evidence: @escaping EvidenceSink
    ) async throws -> Guide {
        do {
            return try await execute(id: id, model: model, facts: facts, measurements: measurements,
                                     weather: weather, stayArea: stayArea, locale: locale, requests: requests,
                                     resolveSuggestion: resolveSuggestion, prepareCandidates: prepareCandidates,
                                     send: send, evidence: evidence)
        } catch {
            await evidence(.failure(message: String(describing: error)))
            throw error
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func execute(
        id: String, model: String, facts: TripFacts, measurements: PipelineInputMeasurements,
        weather: [DayWeather], stayArea: String, locale: String, requests: JSONValue,
        resolveSuggestion: SuggestionResolver?, prepareCandidates: CandidatePreparer?,
        send: @escaping Send, evidence: @escaping EvidenceSink
    ) async throws -> Guide {
        let researched = try await researchStage(
            model: model, facts: facts, measurements: measurements, stayArea: stayArea,
            resolveSuggestion: resolveSuggestion, prepareCandidates: prepareCandidates, send: send, evidence: evidence)
        let draft = try await planStage(id: id, model: model, researched: researched, weather: weather,
                                        requests: requests, send: send, evidence: evidence)
        return try await writeStage(id: id, model: model, researched: researched, draft: draft,
                                    weather: weather, locale: locale, send: send, evidence: evidence)
    }

    // Runs and verifies research, including preparation of any admitted suggestions.
    // swiftlint:disable:next function_parameter_count
    public func researchStage(
        model: String, facts: TripFacts, measurements: PipelineInputMeasurements, stayArea: String,
        resolveSuggestion: SuggestionResolver? = nil, prepareCandidates: CandidatePreparer? = nil,
        send: Send, evidence: EvidenceSink
    ) async throws -> ResearchedPipeline {
        try validateBoundaryBookings(facts)
        return try await research(model: model, facts: facts, measurements: measurements, stayArea: stayArea,
                                  resolveSuggestion: resolveSuggestion, prepareCandidates: prepareCandidates,
                                  send: send, evidence: evidence)
    }

    // Backwards-compatible combined plan and check stages.
    // swiftlint:disable:next function_parameter_count
    public func planStage(
        id: String, model: String, researched: ResearchedPipeline, weather: [DayWeather],
        requests: JSONValue = .object([:]), send: Send, evidence: EvidenceSink
    ) async throws -> PlanDraft {
        let planned = try await initialPlanStage(id: id, model: model, researched: researched, weather: weather,
                                                 requests: requests, send: send, evidence: evidence)
        return try await checkStage(id: id, model: model, researched: researched, planned: planned,
                                    send: send, evidence: evidence)
    }

    // Requests the initial plan without checking or repairing it.
    // swiftlint:disable:next function_parameter_count
    public func initialPlanStage(
        id: String, model: String, researched: ResearchedPipeline, weather: [DayWeather],
        requests: JSONValue = .object([:]), send: Send, evidence: EvidenceSink
    ) async throws -> PlannedPipeline {
        let planPrompt = try PromptLibrary.load("plan")
        let facts = researched.facts
        let measurements = researched.measurements
        let verified = researched.verified
        let scaffold = Guide(id: id, version: 1, status: .draft, trip: facts.trip, bookings: facts.bookings,
                             stay: facts.stay, places: facts.places, days: [], lists: [], tasting: [],
                             practical: facts.practical, sources: facts.sources)
        let planInput = try PipelineInputBuilder.plan(guide: scaffold, measurements: measurements, weather: weather,
                                                      findings: verified.result.findings, requests: requests)
        guard facts.places.allSatisfy({ key, place in
            !key.isEmpty && key == key.trimmingCharacters(in: .whitespacesAndNewlines) && key == place.id
        }) else { throw GuidePipelineError.invalidPlan("Malformed candidate IDs") }
        let planSchema = try output("plan", PlanDraft.schema(candidateIds: facts.places.keys.sorted()))
        let conversation = PipelineConversation(instructions: planPrompt.body, messages: [
            .init(role: .user, content: try PipelineInputBuilder.json(planInput))
        ])
        let request = try conversation.request(model: model, structuredOutput: planSchema,
                                               reasoningEffort: planPrompt.effort)
        let (draft, response): (PlanDraft, ResponsesResult) = try await decoded(
            request, prompt: planPrompt, step: "plan", send: send, evidence: evidence)
        return PlannedPipeline(draft: draft, previousAssistant: response.text,
                               conversation: conversation, planInput: planInput)
    }

    // Checks the saved initial answer and makes at most two repairs, preserving the original conversation.
    // swiftlint:disable:next function_parameter_count
    public func checkStage(
        id: String, model: String, researched: ResearchedPipeline, planned: PlannedPipeline,
        send: Send, evidence: EvidenceSink
    ) async throws -> PlanDraft {
        let facts = researched.facts
        let verified = researched.verified
        let repairPrompt = try PromptLibrary.load("repair")
        let planSchema = try output("plan", PlanDraft.schema(candidateIds: facts.places.keys.sorted()))
        var conversation = planned.conversation
        var draft = planned.draft
        var previousAssistant = planned.previousAssistant
        let assembler = GuideAssembler(walkTimes: walkTimes)
        let checker = PlanChecker(walkTimes: walkTimes)
        for round in 0...2 {
            let problems = draftProblems(draft, facts: facts, findings: verified.result.findings,
                                         planInput: planned.planInput)
            let withTransit = addTransit(draft, facts: facts)
            var issues = problems
            if problems.isEmpty {
                let assembled = assembler.assemble(id: id, facts: facts, draft: withTransit, copy: emptyCopy)
                let reverse = Dictionary(assembled.stopIds.map { ($0.value, $0.key) },
                                         uniquingKeysWith: { first, _ in first })
                issues += checker.check(assembled.guide).map { issue in
                    PlanIssue(severity: issue.severity, kind: issue.kind, date: issue.date,
                              stopId: issue.stopId.map { reverse[$0] ?? $0 }, message: issue.message)
                }
            }
            let accepted = !issues.contains(where: { $0.severity != .info })
                || (round == 2 && !issues.contains(where: { $0.severity == .error }))
            if accepted {
                // Interest misses are reported with the accepted plan only, so they never reach a repair.
                let misses = interestMisses(withTransit, facts: facts, measurements: researched.measurements)
                await evidence(.plan(round: round, issues: issues + misses))
                return withTransit
            }
            await evidence(.plan(round: round, issues: issues))
            guard round < 2 else { throw GuidePipelineError.planErrors(issues) }
            let legs = measuredLegs(withTransit, facts: facts)
            let payload = try PipelineInputBuilder.repair(issues: issues, legs: legs)
            conversation = conversation.appendingRepair(previousAssistant: previousAssistant,
                                                        repairText: repairPrompt.body, payload: payload)
            let request = try conversation.request(model: model, structuredOutput: planSchema,
                                                   reasoningEffort: repairPrompt.effort)
            let (repaired, response): (PlanDraft, ResponsesResult) = try await decoded(
                request, prompt: repairPrompt, step: "repair\(round + 1)", send: send, evidence: evidence)
            draft = repaired
            previousAssistant = response.text
        }
        throw GuidePipelineError.invalidPlan("No accepted plan")
    }

    // Backwards-compatible combined copy and assembly stages.
    // swiftlint:disable:next function_parameter_count
    public func writeStage(
        id: String, model: String, researched: ResearchedPipeline, draft: PlanDraft,
        weather: [DayWeather], locale: String = "en-GB", send: Send, evidence: EvidenceSink
    ) async throws -> Guide {
        let copy = try await copyStage(id: id, model: model, researched: researched, draft: draft,
                                       weather: weather, locale: locale, send: send, evidence: evidence)
        return try await assembleStage(id: id, researched: researched, draft: draft, copy: copy,
                                       weather: weather, evidence: evidence)
    }

    // Writes and checks copy without marking the guide complete.
    // swiftlint:disable:next function_parameter_count
    public func copyStage(
        id: String, model: String, researched: ResearchedPipeline, draft: PlanDraft,
        weather: [DayWeather], locale: String = "en-GB", send: Send, evidence: EvidenceSink
    ) async throws -> GuideCopy {
        let facts = researched.facts
        let measurements = researched.measurements
        let verified = researched.verified
        let assembler = GuideAssembler(walkTimes: walkTimes)
        let writePrompt = try PromptLibrary.load("write")
        let measured = assembler.assemble(id: id, facts: facts, draft: draft, copy: emptyCopy).guide
        let writeInput = try PipelineInputBuilder.write(guide: measured, draft: draft, measurements: measurements,
                                                         weather: weather, findings: verified.result.findings,
                                                         locale: locale)
        let ids = Set(draft.days.flatMap(\.stops).flatMap { [$0.placeId, $0.alternative?.placeId].compactMap { $0 } }
                      + draft.lists.flatMap(\.placeIds))
        let places = ids.filter { facts.places[$0]?.kind.needsCopy == true }.sorted()
        let stopIDs = draft.days.flatMap(\.stops).map(\.id)
        let listKeys = draft.lists.map(\.key)
        let schema = try output("write", GuideCopy.schema(stopIds: stopIDs, placeIds: places, listKeys: listKeys))
        let request = try PipelineRequestFactory.initial(prompt: writePrompt, input: writeInput, model: model,
                                                          structuredOutput: schema)
        var targets = Set(draft.days.map { CopyTarget.day($0.date) })
        targets.formUnion(stopIDs.map { .stop($0) })
        targets.formUnion(places.map { .place($0) })
        targets.formUnion(listKeys.map { .list($0) })
        let inputText = try PipelineInputBuilder.json(writeInput)
        var current = request
        for attempt in 0...1 {
            let (copy, response): (GuideCopy, ResponsesResult) = try await decoded(
                current, prompt: writePrompt, step: "write", send: send, evidence: evidence)
            let issues = CopyChecker().check(copy, expected: targets, input: inputText)
                + stayContradictions(copy, id: id, draft: draft, facts: facts)
            await evidence(.copy(issues: issues))
            let blocking = issues.filter { Self.blocksCopy($0.kind, retried: attempt > 0) }
            if blocking.isEmpty { return await usableCopy(copy, evidence: evidence) }
            guard attempt == 0 else { throw GuidePipelineError.copyErrors(issues) }
            let feedback = blocking.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
            current = ResponsesRequest(model: model, instructions: writePrompt.body, messages: request.messages + [
                .init(role: .assistant, content: response.text),
                .init(role: .user, content: "Correct these copy issues and return the complete JSON:\n" + feedback)
            ], structuredOutput: schema, reasoningEffort: writePrompt.effort)
        }
        throw GuidePipelineError.invalidPlan("No accepted copy")
    }

    /// The copy the guide is built from. Generic tasting items are removed, so a category is never shipped. If that
    /// leaves the tasting list outside 6 to 8 items, the count is flagged for review rather than failing the build.
    private func usableCopy(_ copy: GuideCopy, evidence: EvidenceSink) async -> GuideCopy {
        let used = copy.removingGenericTasting()
        if used.tasting.count != copy.tasting.count, let issue = CopyChecker.tastingCountIssue(used) {
            await evidence(.copy(issues: [issue]))
        }
        return used
    }

    /// Whether a copy issue stops the copy being used. Numbers are never blocking: they are flagged for review. Length
    /// limits and the card and plan checks (opening hours, walks, plan talk, transport) block the first answer, so the
    /// writer is asked to fix them, but not the corrected one: one sentence a word too long, or one stray closing time,
    /// should not throw away a whole guide. They are flagged for review instead. Generic tasting items and a tasting
    /// list of the wrong length follow the same rule: the writer is asked once, and what is left is removed or flagged.
    static func blocksCopy(_ kind: CopyCheckIssue.Kind, retried: Bool) -> Bool {
        switch kind {
        case .ungroundedNumber: false
        case .wordLimit, .sentenceLimit, .hoursInBody, .walkInBody, .planTalk, .inventedTransport: !retried
        case .genericTasting, .tastingCount: !retried
        // A contradiction of the facts always blocks, on both attempts: the facts win over the prose.
        case .stayContradiction: true
        default: true
        }
    }

    /// The copy's words that contradict the facts (see `Guide.contradictions`), as copy issues. The guide is assembled
    /// with this copy, so the check reads the same words the finished guide would show.
    private func stayContradictions(_ copy: GuideCopy, id: String, draft: PlanDraft,
                                    facts: TripFacts) -> [CopyCheckIssue] {
        GuideAssembler(walkTimes: walkTimes).assemble(id: id, facts: facts, draft: draft, copy: copy)
            .guide.contradictions.map {
                CopyCheckIssue(kind: .stayContradiction($0.words), path: $0.path, text: $0.text, note: $0.reason)
            }
    }

    /// Assembles and validates the finished guide; completion is emitted only on success. Each day gets the weather
    /// for its date from `weather`, when there is some. Research facts the plan does not need are left out of the
    /// guide here (see `ResearchFactFilter`); the planner and writer still saw every finding.
    public func assembleStage(
        id: String, researched: ResearchedPipeline, draft: PlanDraft, copy: GuideCopy,
        weather: [DayWeather] = [], evidence: EvidenceSink
    ) async throws -> Guide {
        let facts = ResearchFactFilter.filtered(researched.facts, findings: researched.verified.result.findings,
                                                draft: draft)
        let result = GuideAssembler(walkTimes: walkTimes).assemble(id: id, facts: facts,
                                                                   draft: draft, copy: copy,
                                                                   weather: DayOutlook.outlooks(weather))
        guard result.problems.isEmpty else { throw GuidePipelineError.assemblyProblems(result.problems) }
        try result.guide.validateStructure()
        let finalIssues = PlanChecker(walkTimes: walkTimes).check(result.guide)
        // The final gate: no guide whose words contradict its facts is ever completed. The evidence keeps the issues.
        let contradictions = result.guide.contradictions
        guard contradictions.isEmpty else {
            await evidence(.plan(round: 3, issues: finalIssues))
            throw GuidePipelineError.contradictions(contradictions)
        }
        await evidence(.plan(round: 3, issues: finalIssues))
        guard !finalIssues.contains(where: { $0.severity == .error }) else {
            throw GuidePipelineError.planErrors(finalIssues)
        }
        await evidence(.completed)
        return result.guide
    }
}
private extension GuidePipeline {
    // swiftlint:disable:next function_parameter_count
    func research(model: String, facts: TripFacts, measurements: PipelineInputMeasurements, stayArea: String,
                  resolveSuggestion: SuggestionResolver?, prepareCandidates: CandidatePreparer?,
                  send: Send, evidence: EvidenceSink) async throws -> ResearchedPipeline {
        let prompt = try PromptLibrary.load("research")
        let request = try PipelineRequestFactory.initial(
            prompt: prompt, input: PipelineInputBuilder.research(trip: facts.trip, stayArea: stayArea),
            model: model, structuredOutput: output("research", ResearchResult.schema()))
        let (research, response): (ResearchResult, ResponsesResult) = try await decoded(
            request, prompt: prompt, step: "research", send: send, evidence: evidence)
        let venues = ResearchVerification.venueSuggestions(for: research.findings, reportedURLs: response.sourceURLs,
                                                           existing: research.suggestedPlaces)
        let suggested = ResearchResult(findings: research.findings,
                                       suggestedPlaces: research.suggestedPlaces + venues,
                                       searchNotes: research.searchNotes)
        let resolved = try await ResearchVerification.verify(suggested, sourceURLs: response.sourceURLs) { suggestion in
            try await resolveSuggestion?(suggestion)
        }
        let (prepared, measurements) = try await prepareCandidates?(resolved, facts, measurements)
            ?? (facts, measurements)
        try Task.checkCancellation()
        let admitted = zip(resolved.result.suggestedPlaces, resolved.places).filter { prepared.places[$0.1.id] != nil }
        var notes = resolved.result.searchNotes
        if research.findings.count != resolved.result.findings.count {
            notes += "\nDropped findings with invalid, duplicate, or unreported sources or IDs."
        }
        if suggested.suggestedPlaces.count != admitted.count {
            notes += "\nDropped unresolved or unprepared suggested places."
        }
        let verified = VerifiedResearch(result: ResearchResult(findings: resolved.result.findings,
            suggestedPlaces: admitted.map(\.0), searchNotes: notes), places: admitted.map(\.1))
        await evidence(.research(accepted: verified.result, resolvedPlaceIDs: verified.places.map(\.id)))
        return ResearchedPipeline(facts: researchFacts(prepared, findings: verified.result.findings),
                             measurements: measurements, verified: verified)
    }
    func researchFacts(_ facts: TripFacts, findings: [ResearchFinding]) -> TripFacts {
        var sources = facts.sources
        var practical = facts.practical
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        guard let year = components.year, let month = components.month, let day = components.day,
              let checked = LocalDate(year: year, month: month, day: day) else { return facts }
        for (index, finding) in findings.enumerated() {
            var id = "taba-research-\(index)"
            while sources.contains(where: { $0.id == id }) { id += "-source" }
            sources.append(Source(id: id, url: finding.url, title: finding.sourceTitle, checkedAt: checked))
            practical.append(Fact(text: ResearchFactFilter.factText(for: finding), sourceId: id, checkedAt: checked))
        }
        return TripFacts(trip: facts.trip, bookings: facts.bookings, stay: facts.stay, places: facts.places,
                         practical: practical, sources: sources)
    }

    private func output(_ name: String, _ schema: JSONSchema) throws -> StructuredOutput {
        let data = try JSONEncoder().encode(schema)
        return StructuredOutput(name: name, schema: try JSONDecoder().decode(JSONValue.self, from: data))
    }

    private func decoded<T: Decodable>(
        _ request: ResponsesRequest, prompt: Prompt, step: String, send: Send, evidence: EvidenceSink
    ) async throws -> (T, ResponsesResult) {
        for attempt in 0...1 {
            try Task.checkCancellation()
            await evidence(.request(step: step, promptID: prompt.id, version: prompt.version, request: request))
            let start = ContinuousClock.now
            let result: ResponsesResult
            do {
                result = try await send(request)
            } catch {
                await evidence(.requestFailed(step: step, message: String(describing: error),
                                              seconds: seconds(start.duration(to: .now))))
                throw error
            }
            try Task.checkCancellation()
            await evidence(.response(step: step, result: result, seconds: seconds(start.duration(to: .now))))
            if let status = result.status, status != "completed" {
                throw GuidePipelineError.invalidResponseStatus(status)
            }
            do {
                return (try JSONDecoder().decode(T.self, from: Data(result.text.utf8)), result)
            } catch {
                await evidence(.decodeFailed(step: step, message: String(describing: error)))
                if attempt == 1 { throw error }
            }
        }
        throw GuidePipelineError.invalidPlan("Decode retry exhausted")
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    private var emptyCopy: GuideCopy {
        GuideCopy(hero: GuideHero(title: "", subtitle: "", tagline: ""), days: [], stops: [], places: [], lists: [],
                  tasting: [], notes: GuideNotes(weather: "", light: "", backupPlan: "", rules: ""))
    }

    private func measuredLegs(_ draft: PlanDraft, facts: TripFacts) -> JSONValue {
        .array(draft.days.flatMap { day in
            let stops = day.stops.sorted { $0.start < $1.start }
            return zip(stops, stops.dropFirst()).map { from, to in
                let origin = from.placeId.flatMap { facts.places[$0] }
                let destination = to.placeId.flatMap { facts.places[$0] }
                let mode: JSONValue
                let minutes: JSONValue
                if let origin, let destination {
                    let leg = Travel.leg(from: origin.location.coordinate, to: destination.location.coordinate,
                                         walkTimes: walkTimes)
                    mode = .string(leg.mode.rawValue)
                    minutes = .integer(leg.minutes)
                } else {
                    mode = .null
                    minutes = .null
                }
                return JSONValue.object(["fromStopId": .string(from.id), "toStopId": .string(to.id),
                                         "mode": mode, "minutes": minutes])
            }
        })
    }

    /// One info issue for each trip interest that no stop's place serves, while at least one candidate serves it.
    /// The issue's date is the trip's first day, since the miss is about the whole trip.
    private func interestMisses(_ draft: PlanDraft, facts: TripFacts,
                                measurements: PipelineInputMeasurements) -> [PlanIssue] {
        func served(_ place: Place) -> [String] {
            InterestMatch.interests(for: facts.trip.interests, kind: place.kind, indoor: place.indoor,
                                    searchLabels: measurements.searchLabels[place.id] ?? [])
        }
        let stopPlaces = draft.days.flatMap(\.stops).compactMap { $0.placeId.flatMap { facts.places[$0] } }
        let covered = Set(stopPlaces.flatMap(served))
        let candidates = facts.places.values.map { served($0) }
        var reported = Set<String>()
        return facts.trip.interests.compactMap { interest in
            guard !covered.contains(interest), reported.insert(interest).inserted else { return nil }
            let count = candidates.filter { $0.contains(interest) }.count
            guard count > 0 else { return nil }
            let phrase = count == 1 ? "1 candidate serves it" : "\(count) candidates serve it"
            return PlanIssue(severity: .info, kind: .interestMissed, date: facts.trip.dates.start, stopId: nil,
                             message: "No stop for \(interest), though \(phrase).")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func draftProblems(
        _ draft: PlanDraft, facts: TripFacts, findings: [ResearchFinding], planInput: JSONValue
    ) -> [PlanIssue] {
        var messages: [(LocalDate, String)] = []
        var dates: Set<LocalDate> = []
        var stops: Set<String> = []
        for day in draft.days {
            if !dates.insert(day.date).inserted || day.date < facts.trip.dates.start
                || day.date > facts.trip.dates.end {
                messages.append((day.date, "Duplicate or out-of-range day."))
            }
            let window = planInput.objectValue?["days"]?.arrayValue?.compactMap(\.objectValue).first {
                $0["date"]?.stringValue == day.date.description
            }?["window"]?.objectValue
            let start = window?["start"]?.stringValue.flatMap(LocalTime.init)
            let end = window?["end"]?.stringValue.flatMap(LocalTime.init)
            for stop in day.stops {
                if let start, let end, stop.start < start
                    || stop.minutes > end.minutesSinceMidnight - stop.start.minutesSinceMidnight {
                    messages.append((day.date, "Stop outside planning window: \(stop.id)."))
                }
                if stop.id.isEmpty || stop.id != stop.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    || !stops.insert(stop.id).inserted || stop.id.hasPrefix("taba-transit-") {
                    messages.append((day.date, "Duplicate or reserved stop id: \(stop.id)."))
                }
                if stop.kind == .meal && stop.mealSlot == nil || stop.kind != .meal && stop.mealSlot != nil {
                    messages.append((day.date, "Invalid meal slot for \(stop.id)."))
                }
                if duplicatesTransit(stop, date: day.date, facts: facts) {
                    messages.append((day.date, "Travel stop duplicates a booked arrival or departure: \(stop.id)."))
                }
                if stop.placeId == nil && stop.kind != .meal {
                    messages.append((day.date, "Missing place for \(stop.id)."))
                }
                if stop.findingIds.contains(where: { id in !findings.contains { $0.id == id } }) {
                    messages.append((day.date, "Unknown finding for \(stop.id)."))
                }
                if stop.minutes <= 0 || stop.minutes > 1440 - stop.start.minutesSinceMidnight {
                    messages.append((day.date, "Invalid duration for \(stop.id)."))
                }
                for id in [stop.placeId, stop.alternative?.placeId].compactMap({ $0 }) where facts.places[id] == nil {
                    messages.append((day.date, "Unknown candidate: \(id)."))
                }
            }
        }
        messages += missingDays(dates, facts: facts)
        messages += ticketProblems(draft, facts: facts)
        messages += listProblems(draft, facts: facts)
        return messages.map { date, message in
            PlanIssue(severity: .error, kind: .tightGap, date: date, stopId: nil, message: message)
        }
    }

    private func missingDays(_ dates: Set<LocalDate>, facts: TripFacts) -> [(LocalDate, String)] {
        var result: [(LocalDate, String)] = []
        var date = facts.trip.dates.start
        while date <= facts.trip.dates.end {
            if !dates.contains(date) { result.append((date, "Missing day.")) }
            guard let next = date.adding(days: 1), next > date else { break }
            date = next
        }
        return result
    }
    private func duplicatesTransit(_ stop: PlanDraftStop, date: LocalDate, facts: TripFacts) -> Bool {
        guard stop.kind == .travel else { return false }
        // The arrival and departure the traveller gave count the same as a booking.
        if let travel = facts.trip.travel, stop.placeId != nil {
            let statedArrival = date == facts.trip.dates.start && stop.placeId == travel.arrivalPlaceId
                && facts.trip.dates.arrives == stop.start
            let statedDeparture = date == facts.trip.dates.end && stop.placeId == travel.departurePlaceId
                && facts.trip.dates.leaves == stop.start
            if statedArrival || statedDeparture { return true }
        }
        return facts.bookings.contains { booking in
            func local(_ id: String?, _ name: String) -> Bool {
                (id.map { facts.places[$0] != nil } ?? false)
                    || name.localizedCaseInsensitiveContains(facts.trip.destination.name)
            }
            let fromLocal = local(booking.fromPlaceId, booking.from)
            let toLocal = local(booking.toPlaceId, booking.to)
            return [.train, .flight, .bus].contains(booking.kind)
                && ((date == facts.trip.dates.start && !fromLocal && toLocal
                     && booking.arrives.date == date && booking.arrives.time == stop.start
                     && booking.toPlaceId != nil && booking.toPlaceId == stop.placeId)
                    || (date == facts.trip.dates.end && fromLocal && !toLocal
                        && booking.departs.date == date && booking.departs.time == stop.start
                        && booking.fromPlaceId != nil && booking.fromPlaceId == stop.placeId))
        }
    }

    private func ticketProblems(_ draft: PlanDraft, facts: TripFacts) -> [(LocalDate, String)] {
        facts.bookings.filter { $0.kind == .ticket }.compactMap { booking in
            let ids = [booking.fromPlaceId, booking.toPlaceId].compactMap { $0 }
            let matches = draft.days.filter { $0.date == booking.departs.date }.flatMap(\.stops).filter {
                $0.start == booking.departs.time && $0.placeId.map(ids.contains) == true
            }
            guard matches.count != 1 else { return nil }
            return (booking.departs.date, "Ticket booking \(booking.id) must appear once at its booked time and place.")
        }
    }

    private func listProblems(_ draft: PlanDraft, facts: TripFacts) -> [(LocalDate, String)] {
        var messages: [(LocalDate, String)] = []
        if Set(draft.lists.map(\.key)).count != draft.lists.count {
            messages.append((facts.trip.dates.start, "Duplicate list key."))
        }
        let keys = Set(draft.lists.map(\.key))
        if !Set([ListKey.eat, .drink, .photos]).isSubset(of: keys) {
            messages.append((facts.trip.dates.start, "Missing required list."))
        }
        for list in draft.lists where Set(list.placeIds).count != list.placeIds.count {
            messages.append((facts.trip.dates.start, "Duplicate list candidate."))
        }
        var skipped: Set<String> = []
        for meal in draft.skippedMeals {
            if meal.date < facts.trip.dates.start || meal.date > facts.trip.dates.end
                || !skipped.insert("\(meal.date)-\(meal.slot.rawValue)").inserted
                || meal.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append((meal.date, "Invalid skipped meal."))
            }
        }
        for id in draft.lists.flatMap(\.placeIds) where facts.places[id] == nil {
            messages.append((facts.trip.dates.start, "Unknown list candidate: \(id)."))
        }
        return messages
    }

    /// Unknown boundary endpoints must not silently remove an arrival/departure constraint.
    private func validateBoundaryBookings(_ facts: TripFacts) throws {
        for booking in facts.bookings where [BookingKind.train, .flight, .bus].contains(booking.kind) {
            guard booking.arrives.date == facts.trip.dates.start
                || booking.departs.date == facts.trip.dates.end else { continue }
            let endpoints = [(booking.fromPlaceId, booking.from), (booking.toPlaceId, booking.to)]
            let hasLocalEndpoint = endpoints.contains { id, name in
                (id.map { facts.places[$0] != nil } ?? false)
                    || name.localizedCaseInsensitiveContains(facts.trip.destination.name)
            }
            guard hasLocalEndpoint else {
                throw GuidePipelineError.invalidPlan(
                    "Resolve boundary booking endpoints before planning: \(booking.id)")
            }
        }
    }

    private func addTransit(_ draft: PlanDraft, facts: TripFacts) -> PlanDraft {
        let bookings = facts.bookings.filter { [BookingKind.train, .flight, .bus].contains($0.kind) }
        func local(_ id: String?, _ name: String) -> Bool {
            (id.map { facts.places[$0] != nil } ?? false)
                || name.localizedCaseInsensitiveContains(facts.trip.destination.name)
        }
        let arrival = bookings.filter { $0.arrives.date == facts.trip.dates.start
            && local($0.toPlaceId, $0.to) && !local($0.fromPlaceId, $0.from) }.min { $0.arrives < $1.arrives }
        let departure = bookings.filter { $0.departs.date == facts.trip.dates.end
            && local($0.fromPlaceId, $0.from) && !local($0.toPlaceId, $0.to) }.min { $0.departs < $1.departs }
        func stop(_ id: String, _ place: String?, _ time: LocalTime, reason: String) -> PlanDraftStop {
            PlanDraftStop(id: id, placeId: place, kind: .travel, mealSlot: nil, start: time, minutes: 1,
                          flexible: false, alternative: nil, reason: reason, findingIds: [])
        }
        // A booking gives the arrival and departure. Without one, the place and time the traveller gave do.
        let travel = facts.trip.travel
        let arrivalStop: (date: LocalDate, stop: PlanDraftStop)? = arrival.map {
            ($0.arrives.date, stop("taba-transit-arrival", $0.toPlaceId, $0.arrives.time,
                                   reason: "Fixed transport booking"))
        } ?? travel?.arrivalPlaceId.flatMap { placeId in
            facts.trip.dates.arrives.map {
                (facts.trip.dates.start,
                 stop("taba-transit-arrival", placeId, $0, reason: "Arrival the traveller gave"))
            }
        }
        let departureStop: (date: LocalDate, stop: PlanDraftStop)? = departure.map {
            ($0.departs.date, stop("taba-transit-departure", $0.fromPlaceId, $0.departs.time,
                                   reason: "Fixed transport booking"))
        } ?? travel?.departurePlaceId.flatMap { placeId in
            facts.trip.dates.leaves.map {
                (facts.trip.dates.end,
                 stop("taba-transit-departure", placeId, $0, reason: "Departure the traveller gave"))
            }
        }
        let days = draft.days.map { day in
            var stops = day.stops
            if let arrivalStop, day.date == arrivalStop.date { stops.append(arrivalStop.stop) }
            if let departureStop, day.date == departureStop.date { stops.append(departureStop.stop) }
            return PlanDraftDay(date: day.date, theme: day.theme, stops: stops)
        }
        // Skipped meals stay in the draft for the evidence; they are not questions for the traveller. A pick list
        // keeps only places whose kind fits it, so a misfiled place costs no repair round.
        let lists = draft.lists.map { list in
            DraftList(key: list.key, placeIds: list.placeIds.filter { id in
                guard let kind = facts.places[id]?.kind, let allowed = PlanChecker.listKinds[list.key] else {
                    return true
                }
                return allowed.contains(kind)
            })
        }
        return PlanDraft(days: days, lists: lists, skippedMeals: draft.skippedMeals,
                         openQuestions: draft.openQuestions, changes: draft.changes)
    }
}
