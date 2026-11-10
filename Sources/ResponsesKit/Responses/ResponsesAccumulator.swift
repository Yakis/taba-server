import Foundation

public struct ResponsesUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(inputTokens: Int?, outputTokens: Int?, totalTokens: Int?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

/// The finished answer from a stream that reached response.completed.
public struct ResponsesResult: Sendable, Equatable {
    public let text: String
    public let status: String?
    public let responseId: String?
    public let usage: ResponsesUsage?
    /// Number of web search calls in the response.
    public let webSearchCount: Int
    /// URLs the search read, from `web_search_call.action.sources`. Empty when they were not asked for.
    public let sourceURLs: [String]
    /// URLs cited in the answer text, from `url_citation` annotations.
    public let citationURLs: [String]

    public init(
        text: String,
        status: String?,
        responseId: String?,
        usage: ResponsesUsage?,
        webSearchCount: Int,
        sourceURLs: [String],
        citationURLs: [String]
    ) {
        self.text = text
        self.status = status
        self.responseId = responseId
        self.usage = usage
        self.webSearchCount = webSearchCount
        self.sourceURLs = sourceURLs
        self.citationURLs = citationURLs
    }
}

/// Reads Responses stream events in order and builds the answer. Text, search sources and citations are collected
/// as they arrive. A terminal error event throws. Success needs response.completed.
public struct ResponsesAccumulator: Sendable {
    private var text = ""
    private var completed: [String: JSONValue]?
    private var searchIds: [String] = []
    private var sources: [String] = []
    private var citations: [String] = []
    /// Every web URL found inside a web_search_call item, whatever its field. Used only when sources are recovered.
    private var searchItemURLs: [String] = []

    public init() {}

    public mutating func consume(_ event: SSEEvent) throws(ResponsesError) {
        guard let object = Self.object(from: event) else { return }
        let type = object["type"]?.stringValue ?? event.name ?? ""
        switch type {
        case "response.output_text.delta", "response.output_item.done",
             "response.output_text.annotation.added", "response.completed":
            collect(type: type, object: object)
        case "response.failed", "response.incomplete", "error":
            throw Self.failure(type: type, object: object)
        default:
            break
        }
    }

    /// The answer. Throws when the stream never reached response.completed.
    public func result() throws(ResponsesError) -> ResponsesResult {
        try result(recoveringSourceURLs: false)
    }

    /// The answer. With `recoveringSourceURLs`, a search that returned no sources falls back to the citation URLs and
    /// the URLs in the search items (see `SourceRecovery`).
    public func result(recoveringSourceURLs: Bool) throws(ResponsesError) -> ResponsesResult {
        guard let completed else { throw .streamEndedWithoutCompletion }
        let usage = completed["usage"]?.objectValue.map { object in
            ResponsesUsage(
                inputTokens: object["input_tokens"].flatMap { intValue($0) },
                outputTokens: object["output_tokens"].flatMap { intValue($0) },
                totalTokens: object["total_tokens"].flatMap { intValue($0) }
            )
        }
        let recover = recoveringSourceURLs && sources.isEmpty && !searchIds.isEmpty
        return ResponsesResult(
            text: text,
            status: completed["status"]?.stringValue,
            responseId: completed["id"]?.stringValue,
            usage: usage,
            webSearchCount: searchIds.count,
            sourceURLs: recover ? SourceRecovery.urls(citations: citations, searchItemURLs: searchItemURLs) : sources,
            citationURLs: citations
        )
    }

    private static func object(from event: SSEEvent) -> [String: JSONValue]? {
        guard event.data != "[DONE]",
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8))
        else {
            return nil
        }
        return value.objectValue
    }

    private mutating func collect(type: String, object: [String: JSONValue]) {
        switch type {
        case "response.output_text.delta":
            text += object["delta"]?.stringValue ?? ""
        case "response.output_item.done":
            if let item = object["item"]?.objectValue {
                record(item)
            }
        case "response.output_text.annotation.added":
            if let annotation = object["annotation"]?.objectValue {
                addCitation(annotation)
            }
        default:
            completed = object["response"]?.objectValue
            for item in completed?["output"]?.arrayValue ?? [] {
                if let item = item.objectValue { record(item) }
            }
        }
    }

    private static func failure(type: String, object: [String: JSONValue]) -> ResponsesError {
        switch type {
        case "response.failed":
            return error(from: object["response"]?.objectValue?["error"]?.objectValue)
        case "response.incomplete":
            let details = object["response"]?.objectValue?["incomplete_details"]?.objectValue
            return .incomplete(reason: details?["reason"]?.stringValue)
        default:
            return error(from: object)
        }
    }

    private mutating func record(_ item: [String: JSONValue]) {
        switch item["type"]?.stringValue {
        case "web_search_call":
            recordSearch(item)
        case "message":
            for part in item["content"]?.arrayValue ?? [] {
                for annotation in part.objectValue?["annotations"]?.arrayValue ?? [] {
                    if let object = annotation.objectValue { addCitation(object) }
                }
            }
        default:
            break
        }
    }

    private mutating func recordSearch(_ item: [String: JSONValue]) {
        if let id = item["id"]?.stringValue, !searchIds.contains(id) {
            searchIds.append(id)
        }
        for source in item["action"]?.objectValue?["sources"]?.arrayValue ?? [] {
            if let url = source.objectValue?["url"]?.stringValue, !sources.contains(url) {
                sources.append(url)
            }
        }
        for url in SourceRecovery.webURLs(in: .object(item)) where !searchItemURLs.contains(url) {
            searchItemURLs.append(url)
        }
    }

    private mutating func addCitation(_ annotation: [String: JSONValue]) {
        guard annotation["type"]?.stringValue == "url_citation", let url = annotation["url"]?.stringValue,
              !citations.contains(url)
        else {
            return
        }
        citations.append(url)
    }

    private static func error(from object: [String: JSONValue]?) -> ResponsesError {
        .structured(
            code: object?["code"]?.stringValue,
            param: object?["param"]?.stringValue,
            message: object?["message"]?.stringValue,
            status: nil
        )
    }

    private func intValue(_ value: JSONValue) -> Int? {
        switch value {
        case .integer(let number): number
        case .number(let number): Int(number)
        default: nil
        }
    }
}

/// Source URLs for a provider that leaves `web_search_call.action.sources` out (DeepSeek).
enum SourceRecovery {
    /// The citation URLs first, then the search-item URLs, without repeats, keeping only web addresses.
    static func urls(citations: [String], searchItemURLs: [String]) -> [String] {
        var seen = Set<String>()
        return (citations + searchItemURLs).filter { url in
            isWebURL(url) && seen.insert(url).inserted
        }
    }

    /// Every string value in the JSON that is an http or https address, in document order.
    static func webURLs(in value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            isWebURL(text) ? [text] : []
        case .array(let items):
            items.flatMap(webURLs(in:))
        case .object(let object):
            object.keys.sorted().flatMap { webURLs(in: object[$0] ?? .null) }
        default:
            []
        }
    }

    private static func isWebURL(_ text: String) -> Bool {
        (text.hasPrefix("https://") || text.hasPrefix("http://")) && !text.contains(where: \.isWhitespace)
    }
}
