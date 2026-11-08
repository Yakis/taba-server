import Foundation

/// A strict JSON schema for the answer, sent as `text.format`.
public struct StructuredOutput: Sendable, Hashable {
    public let name: String
    public let schema: JSONValue

    public init(name: String, schema: JSONValue) {
        self.name = name
        self.schema = schema
    }
}

/// A Responses request for the ChatGPT plan route. Only the fields the route accepts can be set. `store` is always
/// false and `stream` always true, and `instructions` replaces any system message.
public struct ResponsesRequest: Sendable {
    /// Fields the route rejects. The body never includes them, and a test checks that.
    public static let rejectedParameters: [String] = [
        "background", "conversation", "max_output_tokens", "max_tool_calls", "metadata", "moderation",
        "multi_agent", "previous_response_id", "prompt", "prompt_cache_retention", "safety_identifier",
        "temperature", "top_logprobs", "top_p", "truncation", "user"
    ]

    public let model: String
    public let instructions: String
    public let userText: String
    public let structuredOutput: StructuredOutput?
    public let webSearch: Bool
    /// Asks for the full list of URLs the search read, as `web_search_call.action.sources`.
    public let includeSearchSources: Bool
    public let reasoningEffort: String?

    public init(
        model: String,
        instructions: String,
        userText: String,
        structuredOutput: StructuredOutput? = nil,
        webSearch: Bool = false,
        includeSearchSources: Bool = false,
        reasoningEffort: String? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.userText = userText
        self.structuredOutput = structuredOutput
        self.webSearch = webSearch
        self.includeSearchSources = includeSearchSources
        self.reasoningEffort = reasoningEffort
    }

    /// The JSON body for `POST /v1/responses`.
    public func body() throws -> Data {
        try Self.encode(object())
    }

    /// The body with one extra field. Only the probe's rejected-parameter check uses this, to confirm the docs.
    public func body(addingRejectedParameter name: String, value: JSONValue) throws -> Data {
        var object = object()
        object[name] = value
        return try Self.encode(object)
    }

    func object() -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "model": .string(model),
            "instructions": .string(instructions),
            "input": .array([.object(["role": .string("user"), "content": .string(userText)])]),
            "store": .bool(false),
            "stream": .bool(true)
        ]
        if let output = structuredOutput {
            let format: [String: JSONValue] = [
                "type": .string("json_schema"),
                "name": .string(output.name),
                "strict": .bool(true),
                "schema": output.schema
            ]
            object["text"] = .object(["format": .object(format)])
        }
        if webSearch {
            object["tools"] = .array([.object(["type": .string("web_search")])])
        }
        if includeSearchSources {
            object["include"] = .array([.string("web_search_call.action.sources")])
        }
        if let reasoningEffort {
            object["reasoning"] = .object(["effort": .string(reasoningEffort)])
        }
        return object
    }

    static func encode(_ object: [String: JSONValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(object)
    }
}
