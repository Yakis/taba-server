import Foundation
@testable import ResponsesKit
import Testing

struct AnthropicMessagesTests {
    private let schemaText = #"""
    {"type":"object","additionalProperties":false,"required":["count","title","pattern"],
     "properties":{
       "count":{"type":"integer","minimum":1,"maximum":9},
       "title":{"type":"string","minLength":2,"pattern":"^[A-Z]"},
       "pattern":{"type":"string"},
       "tags":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"string","maxLength":20}},
       "mood":{"type":"string","enum":["minimum","calm"]}
     }}
    """#

    private func schema() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(schemaText.utf8))
    }

    private func request(search: Bool = false, withSchema: Bool = false, effort: String? = nil) throws
        -> ResponsesRequest {
        ResponsesRequest(
            model: "claude-opus-5-5",
            instructions: "Write the guide.",
            messages: [
                ResponsesMessage(role: .user, content: "Plan the trip."),
                ResponsesMessage(role: .assistant, content: "Draft one."),
                ResponsesMessage(role: .user, content: "Now the copy.")
            ],
            structuredOutput: withSchema ? StructuredOutput(name: "guide", schema: try schema()) : nil,
            webSearch: search,
            reasoningEffort: effort
        )
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aPlainRequestHasNoSearchNoFormatAndNoSamplingFields() throws {
        let body = try object(try AnthropicMessages.body(for: try request()))
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["max_tokens"] as? Int == 64_000)
        #expect(body["stream"] as? Bool == true)
        #expect(body["system"] as? String == "Write the guide.")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["tools"] == nil)
        let config = try #require(body["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "high")
        #expect(config["format"] == nil)
        for name in ["thinking", "temperature", "top_p", "top_k"] {
            #expect(body[name] == nil, "\(name) must not be sent")
        }
    }

    @Test func messagesKeepTheirRolesAndOrder() throws {
        let body = try object(try AnthropicMessages.body(for: try request()))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        #expect(messages.map { $0["content"] as? String } == ["Plan the trip.", "Draft one.", "Now the copy."])
    }

    @Test func webSearchAndTheSchemaAreSentInAnthropicsShape() throws {
        let body = try object(try AnthropicMessages.body(for: try request(search: true, withSchema: true)))
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["type"] as? String == "web_search_20260209")
        #expect(tools.first?["name"] as? String == "web_search")
        #expect(tools.first?["max_uses"] as? Int == 10)
        let config = try #require(body["output_config"] as? [String: Any])
        let format = try #require(config["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] == nil)
        let sent = try #require(format["schema"] as? [String: Any])
        #expect(sent["additionalProperties"] as? Bool == false)
    }

    @Test func unsupportedSchemaKeywordsAreRemovedAtEveryDepth() throws {
        let sent = AnthropicMessages.strippedSchema(try schema())
        let properties = try #require(sent.objectValue?["properties"]?.objectValue)
        let count = try #require(properties["count"]?.objectValue)
        #expect(count["type"] == .string("integer"))
        #expect(count["minimum"] == nil && count["maximum"] == nil)
        let title = try #require(properties["title"]?.objectValue)
        #expect(title["minLength"] == nil && title["pattern"] == nil)
        let tags = try #require(properties["tags"]?.objectValue)
        #expect(tags["minItems"] == nil && tags["maxItems"] == nil)
        let items = try #require(tags["items"]?.objectValue)
        #expect(items["maxLength"] == nil)
        #expect(sent.objectValue?["additionalProperties"] == .bool(false))
    }

    @Test func aPropertyNamedLikeAKeywordIsKeptAndEnumValuesAreUntouched() throws {
        let sent = AnthropicMessages.strippedSchema(try schema())
        let properties = try #require(sent.objectValue?["properties"]?.objectValue)
        // "pattern" is a property name here, not the keyword.
        #expect(properties["pattern"] == .object(["type": .string("string")]))
        let mood = try #require(properties["mood"]?.objectValue)
        #expect(mood["enum"] == .array([.string("minimum"), .string("calm")]))
    }

    @Test func effortMapsToTheAnthropicLevels() throws {
        #expect(AnthropicMessages.effort(nil) == "high")
        #expect(AnthropicMessages.effort("minimal") == "low")
        #expect(AnthropicMessages.effort("low") == "low")
        #expect(AnthropicMessages.effort("medium") == "medium")
        #expect(AnthropicMessages.effort("high") == "high")
        #expect(AnthropicMessages.effort("xhigh") == "xhigh")
        #expect(AnthropicMessages.effort("unknown") == "high")
        let body = try object(try AnthropicMessages.body(for: try request(effort: "medium")))
        let config = try #require(body["output_config"] as? [String: Any])
        #expect(config["effort"] as? String == "medium")
    }

    @Test func aContinuationIsAppendedAfterTheMessages() throws {
        let paused = JSONValue.object(["role": .string("assistant"), "content": .array([.object([
            "type": .string("text"), "text": .string("Searching.")
        ])])])
        let options = AnthropicMessages.Options(continuation: [paused])
        let body = try object(try AnthropicMessages.body(for: try request(search: true), options: options))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 4)
        #expect(messages.last?["role"] as? String == "assistant")
        #expect((messages.last?["content"] as? [Any])?.count == 1)
    }

    @Test func theSchemaRetryTurnsFormatOffAndAddsTheSchemaToTheSystemPrompt() throws {
        let options = AnthropicMessages.Options(includeFormat: false, systemSuffix: "Reply with JSON only.")
        let body = try object(try AnthropicMessages.body(for: try request(withSchema: true), options: options))
        let config = try #require(body["output_config"] as? [String: Any])
        #expect(config["format"] == nil)
        #expect(body["system"] as? String == "Write the guide.\n\nReply with JSON only.")
    }
}
