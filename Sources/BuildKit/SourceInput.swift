import Foundation
import GuideKit
import ResponsesKit

/// Source inputs are values, never paths or provider configuration.
public struct SourceInput: Sendable {
    public let destination: String
    public let from: LocalDate
    public let to: LocalDate
    public let stay: String?
    public let facts: Guide?

    public init(destination: String, from: LocalDate, to: LocalDate, stay: String? = nil, facts: Guide? = nil) {
        self.destination = destination
        self.from = from
        self.to = to
        self.stay = stay
        self.facts = facts
    }
}

public enum SourcePreparationError: Error, Sendable {
    case factsMismatch, geocoding, noCandidates, service
}

public typealias SourceEvidenceSink = @Sendable ([String: JSONValue]) async -> Void

/// Source evidence has no dependency on CLI storage.
public struct SourceRecord: Sendable {
    private let sink: SourceEvidenceSink
    public init(_ sink: @escaping SourceEvidenceSink) { self.sink = sink }
    public func append(_ fields: [String: JSONValue]) async { await sink(fields) }
    public func check() async throws {}
}

func value<T: Encodable>(_ item: T) -> JSONValue {
    guard let data = try? JSONEncoder().encode(item),
          let result = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
    return result
}
