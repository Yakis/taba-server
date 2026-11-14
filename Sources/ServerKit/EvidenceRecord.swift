import Foundation
import PipelineKit
import ResponsesKit

public struct CopyReviewFlag: Codable, Sendable {
    public let path: String
    public let kind: String
    public let text: String?

    init(_ issue: CopyCheckIssue) {
        path = issue.path
        kind = String(describing: issue.kind)
        text = issue.text
    }
}

/// Stored only in the private database. Never returned by SSE or written to logs.
struct EvidenceRecord: Encodable {
    let fields: [String: JSONValue]

    // One exhaustive mapping preserves every evidence event in its private wire format.
    // swiftlint:disable:next cyclomatic_complexity
    init(_ event: BuildEvidence) throws {
        switch event {
        case .source(let source): fields = source
        case .pipeline(let pipeline):
            switch pipeline {
            case let .request(step, promptID, version, request):
                fields = ["event": .string("request"), "step": .string(step), "prompt": .string(promptID),
                          "version": .integer(version),
                          "request": try JSONDecoder().decode(JSONValue.self, from: request.body())]
            case let .response(step, result, seconds):
                fields = ["event": .string("response"), "step": .string(step), "answer": .string(result.text),
                          "seconds": .number(seconds), "status": .string(result.status ?? ""),
                          "sources": try Self.value(result.sourceURLs), "usage": try Self.value(result.usage)]
            case let .requestFailed(step, message, seconds):
                // The error says why: the HTTP status, and the provider's own message when it sent one. Errors
                // never carry a key or a token. Long messages are cut.
                fields = ["event": .string("requestFailed"), "step": .string(step), "seconds": .number(seconds),
                          "message": .string(String(message.prefix(500)))]
            case let .decodeFailed(step, _):
                fields = ["event": .string("decodeFailed"), "step": .string(step)]
            case let .research(accepted, ids):
                fields = ["event": .string("research"), "accepted": try Self.value(accepted),
                          "resolvedPlaceIDs": try Self.value(ids)]
            case let .plan(round, issues):
                fields = ["event": .string("plan"), "round": .integer(round), "issues": try Self.value(issues)]
            case let .copy(issues):
                fields = ["event": .string("copy"), "issues": try Self.value(issues.map(CopyReviewFlag.init))]
            case .failure:
                fields = ["event": .string("failure"), "category": .string("pipelineFailure")]
            case .completed:
                fields = ["event": .string("completed")]
            }
        }
    }

    private static func value<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}
