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

/// A text message in the Responses input conversation.
public struct ResponsesMessage: Sendable, Hashable {
    public enum Role: String, Sendable, Hashable { case user, assistant }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
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
    /// The first user message, retained for compatibility with single-message callers.
    public var userText: String { messages.first(where: { $0.role == .user })?.content ?? "" }
    public let messages: [ResponsesMessage]
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
        self.init(model: model, instructions: instructions,
                  messages: [.init(role: .user, content: userText)], structuredOutput: structuredOutput,
                  webSearch: webSearch, includeSearchSources: includeSearchSources, reasoningEffort: reasoningEffort)
    }

    public init(
        model: String,
        instructions: String,
        messages: [ResponsesMessage],
        structuredOutput: StructuredOutput? = nil,
        webSearch: Bool = false,
        includeSearchSources: Bool = false,
        reasoningEffort: String? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.messages = messages
        self.structuredOutput = structuredOutput
        self.webSearch = webSearch
        self.includeSearchSources = includeSearchSources
        self.reasoningEffort = reasoningEffort
    }

    /// The same request for another model id. Used when a provider serves a model under a different id.
    public func replacingModel(_ model: String) -> ResponsesRequest {
        ResponsesRequest(model: model, instructions: instructions, messages: messages,
                         structuredOutput: structuredOutput, webSearch: webSearch,
                         includeSearchSources: includeSearchSources, reasoningEffort: reasoningEffort)
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
            "input": .array(messages.map { .object(["role": .string($0.role.rawValue),
                                                       "content": .string($0.content)]) }),
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
