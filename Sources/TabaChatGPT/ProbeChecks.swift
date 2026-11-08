import Foundation
import ResponsesKit

/// The five checks. Each one returns a record for the report. None of them uses an API key.
extension ProbeContext {
    static let planPrompt = "plan.md"
    static let researchPrompt = "research.md"

    func basic(key: String = "a-basic", title: String = "a. basic") async -> ProbeRecord {
        let request = ResponsesRequest(model: model, instructions: "Reply with one word.", userText: "Say hello.")
        return await inference(key: key, title: title, request: request)
    }

    func planSchema() async -> ProbeRecord {
        let key = "b-schema"
        let title = "b. strict schema"
        guard let instructions = await PromptLoader.instructions(named: Self.planPrompt) else {
            return .skipped(key: key, title: title, reason: "skipped: Prompts/plan.md not found")
        }
        let candidates = ProbeCandidates.all
        let request = ResponsesRequest(
            model: model,
            instructions: instructions,
            userText: ProbeCandidates.planInput,
            structuredOutput: ProbeSchemas.planDraft(candidateIds: candidates.map(\.id))
        )
        let record = await inference(key: key, title: title, request: request)
        guard let body = record.rawBody, let text = ProbeCandidates.outputText(fromRawBody: body) else {
            return record
        }
        let check = ProbeChecks.planDraft(text, candidateIds: Set(candidates.map(\.id)))
        let line = "\(record.line); decodes: \(check.decodes), schema: \(check.schemaValid), "
            + "placeIds from candidates: \(check.placeIdsFromCandidates), stops: \(check.stopCount)"
        return ProbeRecord(key: record.key, title: record.title, line: line,
                           detail: check.problems, rawBody: record.rawBody)
    }

    func webSearchSchema() async -> ProbeRecord {
        let key = "c-web-search"
        let title = "c. web search with strict schema"
        guard let instructions = await PromptLoader.instructions(named: Self.researchPrompt) else {
            return .skipped(key: key, title: title, reason: "skipped: Prompts/research.md not found")
        }
        let request = ResponsesRequest(
            model: model,
            instructions: instructions,
            userText: ProbeCandidates.researchInput,
            structuredOutput: ProbeSchemas.research,
            webSearch: true,
            includeSearchSources: true
        )
        let record = await inference(key: key, title: title, request: request)
        guard let body = record.rawBody, let parsed = ProbeCandidates.parseStream(body) else {
            return record
        }
        let check = ProbeChecks.research(parsed.text, sourceURLs: parsed.sources)
        let calls = "web_search calls: \(parsed.searchCalls), sources in stream: \(parsed.sources.count)"
        let findings = "findings with a source url: \(check.findingsWithSourceURL) of \(check.findingCount)"
        let line = "\(record.line); \(calls), \(findings)"
        return ProbeRecord(key: record.key, title: record.title, line: line,
                           detail: check.problems + check.unmatchedURLs, rawBody: record.rawBody)
    }

    func forcedRefresh() async -> ProbeRecord {
        let key = "d-refresh"
        let title = "d. forced refresh"
        guard await budget.spend() else {
            return .skipped(key: key, title: title, reason: "not sent: request limit reached")
        }
        let started = ContinuousClock.now
        do {
            _ = try await session.credentials(forceRefresh: true)
            let milliseconds = started.duration(to: .now).components.seconds * 1000
            return ProbeRecord(key: key, title: title, line: "ok, refreshed and saved (\(milliseconds) ms)",
                               detail: [], rawBody: nil)
        } catch {
            return ProbeRecord(key: key, title: title, line: "refresh failed: \(ProbeDescribe.error(error))",
                               detail: [], rawBody: nil)
        }
    }

    /// Sends a temperature the docs say is rejected, to confirm the rejection. The only place this is sent.
    func rejectedTemperature() async -> ProbeRecord {
        let key = "e-rejected"
        let title = "e. rejected parameter (temperature)"
        let base = ResponsesRequest(model: model, instructions: "Reply with one word.", userText: "Say hello.")
        guard let body = try? base.body(addingRejectedParameter: "temperature", value: .number(0.2)) else {
            return .skipped(key: key, title: title, reason: "could not build the body")
        }
        guard await budget.spend() else {
            return .skipped(key: key, title: title, reason: "not sent: request limit reached")
        }
        do {
            let credentials = try await session.credentials()
            let outcome = await client.send(body: body, accessToken: credentials.accessToken)
            let line = outcome.error.map { "rejected as the docs say: \(ProbeDescribe.responsesError($0))" }
                ?? "accepted, although the docs say it is rejected"
            return ProbeRecord(key: key, title: title, line: line, detail: [], rawBody: outcome.rawBody)
        } catch {
            return .skipped(key: key, title: title, reason: "not sent: \(ProbeDescribe.error(error))")
        }
    }
}
