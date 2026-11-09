import Foundation
import PipelineKit
import ResponsesKit

actor RunRecord {
    private let url: URL
    private var events: [[String: JSONValue]] = []
    private var failed = false

    init(directory: URL) throws {
        url = directory.appendingPathComponent("run.json")
        try Self.save([], to: url)
    }

    private static func save(_ events: [[String: JSONValue]], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(events).write(to: url, options: [.atomic])
    }

    func append(_ fields: [String: JSONValue]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        events.append(fields.merging(["at": .string(timestamp)]) { first, _ in first })
        do { try Self.save(events, to: url) } catch { failed = true }
    }

    func check() throws { if failed { throw CLIError.recording } }

    func transport(_ outcome: ResponsesOutcome, attempt: Int) {
        let category: String
        switch outcome.error {
        case .usageLimitExceeded: category = "usageLimitExceeded"
        case .usageUnavailable: category = "usageUnavailable"
        case .apiError: category = "apiError"
        case .admissionRejected: category = "admissionRejected"
        case .incomplete: category = "incomplete"
        case .streamEndedWithoutCompletion: category = "streamEndedWithoutCompletion"
        case .transport: category = "transport"
        case nil: category = "none"
        }
        append(["event": .string("transport"), "attempt": .integer(attempt),
                "status": outcome.status.map { .integer($0) } ?? .null, "category": .string(category)])
    }

    func record(_ event: PipelineEvidence) {
        var fields: [String: JSONValue] = [:]
        switch event {
        case let .request(step, promptID, version, request):
            fields = ["event": .string("request"), "step": .string(step), "prompt": .string(promptID),
                      "version": .integer(version),
                      "request": (try? JSONDecoder().decode(JSONValue.self, from: request.body())) ?? .null]
            print("\(step)...")
        case let .response(step, result, seconds):
            fields = ["event": .string("response"), "step": .string(step), "answer": .string(result.text),
                      "seconds": .number(seconds), "status": .string(result.status ?? ""),
                      "sources": .array(result.sourceURLs.map { .string($0) }), "usage": value(result.usage)]
        case let .requestFailed(step, _, seconds):
            fields = ["event": .string("requestFailed"), "step": .string(step), "seconds": .number(seconds)]
        case let .decodeFailed(step, _):
            fields = ["event": .string("decodeFailed"), "step": .string(step)]
        case let .research(accepted, ids):
            fields = ["event": .string("research"), "accepted": value(accepted),
                      "resolvedPlaceIDs": .array(ids.map { .string($0) })]
        case let .plan(round, issues):
            fields = ["event": .string("plan"), "round": .integer(round), "issues": value(issues)]
        case let .copy(issues):
            fields = ["event": .string("copy"), "issues": .array(issues.map { .string(String(describing: $0)) })]
        case .failure:
            fields = ["event": .string("failure"), "message": .string("Pipeline failed; see prior events.")]
        case .completed:
            fields = ["event": .string("completed")]
        }
        append(fields)
    }
}

func value<T: Encodable>(_ item: T) -> JSONValue {
    guard let data = try? JSONEncoder().encode(item), let result = try? JSONDecoder().decode(JSONValue.self, from: data)
    else { return .null }
    return result
}
