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
            await evidence(.plan(round: round, issues: issues))
            if !issues.contains(where: { $0.severity != .info })
                || (round == 2 && !issues.contains(where: { $0.severity == .error })) {
                return withTransit
            }
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
            await evidence(.copy(issues: issues))
            let blocking = issues.filter { if case .ungroundedNumber = $0.kind { false } else { true } }
            if blocking.isEmpty { return copy }
            guard attempt == 0 else { throw GuidePipelineError.copyErrors(issues) }
            let feedback = blocking.map { "\($0.path): \(String(describing: $0.kind))" }.joined(separator: "\n")
            current = ResponsesRequest(model: model, instructions: writePrompt.body, messages: request.messages + [
                .init(role: .assistant, content: response.text),
                .init(role: .user, content: "Correct these copy issues and return the complete JSON:\n" + feedback)
            ], structuredOutput: schema, reasoningEffort: writePrompt.effort)
        }
        throw GuidePipelineError.invalidPlan("No accepted copy")
    }

    /// Assembles and validates the finished guide; completion is emitted only on success. Each day gets the weather
    /// for its date from `weather`, when there is some.
    public func assembleStage(
        id: String, researched: ResearchedPipeline, draft: PlanDraft, copy: GuideCopy,
        weather: [DayWeather] = [], evidence: EvidenceSink
    ) async throws -> Guide {
        let result = GuideAssembler(walkTimes: walkTimes).assemble(id: id, facts: researched.facts,
                                                                   draft: draft, copy: copy,
                                                                   weather: DayOutlook.outlooks(weather))
        guard result.problems.isEmpty else { throw GuidePipelineError.assemblyProblems(result.problems) }
        try result.guide.validateStructure()
        let finalIssues = PlanChecker(walkTimes: walkTimes).check(result.guide)
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
        let resolved = try await ResearchVerification.verify(research, sourceURLs: response.sourceURLs) { suggestion in
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
        if research.suggestedPlaces.count != admitted.count {
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
            practical.append(Fact(text: "\(finding.title): \(finding.summary)", sourceId: id, checkedAt: checked))
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
                let minutes: JSONValue = if let origin, let destination {
                    .integer(walkTimes.minutes(from: origin.location.coordinate, to: destination.location.coordinate))
                } else { .null }
                return JSONValue.object(["fromStopId": .string(from.id), "toStopId": .string(to.id),
                                         "minutes": minutes])
            }
        })
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
        func stop(_ id: String, _ place: String?, _ time: LocalTime) -> PlanDraftStop {
            PlanDraftStop(id: id, placeId: place, kind: .travel, mealSlot: nil, start: time, minutes: 1,
                          flexible: false, alternative: nil, reason: "Fixed transport booking", findingIds: [])
        }
        let days = draft.days.map { day in
            var stops = day.stops
            if let arrival, day.date == arrival.arrives.date {
                stops.append(stop("taba-transit-arrival", arrival.toPlaceId, arrival.arrives.time))
            }
            if let departure, day.date == departure.departs.date {
                stops.append(stop("taba-transit-departure", departure.fromPlaceId, departure.departs.time))
            }
            return PlanDraftDay(date: day.date, theme: day.theme, stops: stops)
        }
        let skippedNotes = draft.skippedMeals.map { "Skipped \($0.slot.rawValue) on \($0.date): \($0.reason)" }
        return PlanDraft(days: days, lists: draft.lists, skippedMeals: draft.skippedMeals,
                         openQuestions: draft.openQuestions + skippedNotes, changes: draft.changes)
    }
}
