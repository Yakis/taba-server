import Foundation

/// Builds the body of `POST /v1/messages` from the same `ResponsesRequest` the ChatGPT route takes. Pure: no network.
public enum AnthropicMessages {
    public static let endpoint = "https://api.anthropic.com/v1/messages"
    public static let version = "2026-10-21"
    public static let beta = "server-side-fallback-2026-07-01"
    public static let providerName = "Claude"
    static let maxTokens = 64_000
    static let maxSearches = 10
    static let webSearchTool = "web_search_20260209"

    /// Per-request switches. The schema-rejection retry turns `format` off and puts the schema in the system prompt.
    public struct Options: Sendable, Equatable {
        public var includeFormat: Bool
        public var systemSuffix: String?
        /// Messages appended after the request's own messages, such as the content a `pause_turn` answer sent back.
        public var continuation: [JSONValue]

        public init(includeFormat: Bool = true, systemSuffix: String? = nil, continuation: [JSONValue] = []) {
            self.includeFormat = includeFormat
            self.systemSuffix = systemSuffix
            self.continuation = continuation
        }
    }

    /// The request object. Never sends thinking, temperature, top_p or top_k: these models reject them.
    public static func object(for request: ResponsesRequest, options: Options = Options()) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "model": .string(request.model),
            "max_tokens": .integer(maxTokens),
            "stream": .bool(true),
            "system": .string(system(request.instructions, suffix: options.systemSuffix)),
            "messages": .array(messages(request.messages) + options.continuation),
            "output_config": .object(outputConfig(request, options: options)),
            "fallbacks": .string("default")
        ]
        if request.webSearch {
            object["tools"] = .array([.object([
                "type": .string(webSearchTool),
                "name": .string("web_search"),
                "max_uses": .integer(maxSearches)
            ])])
        }
        return object
    }

    public static func body(for request: ResponsesRequest, options: Options = Options()) throws -> Data {
        try ResponsesRequest.encode(object(for: request, options: options))
    }

    /// `minimal` and `low` become `low`, `medium`, `high` and `xhigh` pass through, and anything else (or nothing)
    /// is `high`.
    public static func effort(_ reasoningEffort: String?) -> String {
        switch reasoningEffort {
        case "minimal", "low": "low"
        case "medium": "medium"
        case "xhigh": "xhigh"
        default: "high"
        }
    }

    /// Anthropic does not accept these JSON Schema keywords, so they are removed at every depth.
    static let unsupportedKeywords: Set<String> = [
        "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf",
        "minLength", "maxLength", "minItems", "maxItems", "pattern"
    ]

    /// Keys whose value maps names to schemas. Their keys are property names, so they are never treated as keywords.
    static let schemaMaps: Set<String> = ["properties", "$defs", "definitions"]

    /// Keys whose value is data, not schema. Left exactly as they are.
    static let dataKeys: Set<String> = ["enum", "const", "default", "examples"]

    /// The schema with the unsupported keywords removed. Every object keeps its `additionalProperties: false`.
    public static func strippedSchema(_ schema: JSONValue) -> JSONValue {
        switch schema {
        case .object(let object):
            var result: [String: JSONValue] = [:]
            for (key, value) in object {
                if unsupportedKeywords.contains(key) {
                    continue
                } else if dataKeys.contains(key) {
                    result[key] = value
                } else if schemaMaps.contains(key), case .object(let names) = value {
                    result[key] = .object(names.mapValues(strippedSchema))
                } else {
                    result[key] = strippedSchema(value)
                }
            }
            return .object(result)
        case .array(let items):
            return .array(items.map(strippedSchema))
        default:
            return schema
        }
    }

    /// The system prompt, with the optional suffix on its own paragraph.
    static func system(_ instructions: String, suffix: String?) -> String {
        guard let suffix, !suffix.isEmpty else { return instructions }
        return instructions.isEmpty ? suffix : instructions + "\n\n" + suffix
    }

    private static func messages(_ messages: [ResponsesMessage]) -> [JSONValue] {
        messages.map { .object(["role": .string($0.role.rawValue), "content": .string($0.content)]) }
    }

    private static func outputConfig(_ request: ResponsesRequest, options: Options) -> [String: JSONValue] {
        var config: [String: JSONValue] = ["effort": .string(effort(request.reasoningEffort))]
        if options.includeFormat, let output = request.structuredOutput {
            config["format"] = .object([
                "type": .string("json_schema"),
                "schema": strippedSchema(output.schema)
            ])
        }
        return config
    }
}
