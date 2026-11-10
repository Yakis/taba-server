import Foundation
@testable import ResponsesKit
import Testing

struct AnthropicClientTests {
    private let anthropicKey = "anthropic-key-not-real-0001"

    private func request(search: Bool = false, withSchema: Bool = false) throws -> ResponsesRequest {
        let schemaJSON = #"{"type":"object","properties":{"title":{"type":"string","minLength":1}}}"#
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(schemaJSON.utf8))
        return ResponsesRequest(
            model: "claude-sonnet-5-5",
            instructions: "Write.",
            userText: "Plan.",
            structuredOutput: withSchema ? StructuredOutput(name: "guide", schema: schema) : nil,
            webSearch: search,
            reasoningEffort: "low"
        )
    }

    /// A complete turn: an optional search result block, then the answer text.
    private func turn(_ text: String, stop: String = "end_turn", sources: [String] = []) -> [String] {
        var events = [#"{"type":"message_start","message":{"id":"msg_t","usage":{"input_tokens":10}}}"#]
        var index = 0
        if !sources.isEmpty {
            let results = sources.map { #"{"type":"web_search_result","url":"\#($0)","title":"Source"}"# }
            let content = results.joined(separator: ",")
            events.append(#"{"type":"content_block_start","index":0,"content_block":{"type":"web_search_tool_result","#
                + #""tool_use_id":"srv","content":[\#(content)]}}"#)
            events.append(#"{"type":"content_block_stop","index":0}"#)
            index = 1
        }
        events.append(#"{"type":"content_block_start","index":\#(index),"content_block":{"type":"text","text":""}}"#)
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let delta = #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"text_delta","#
            + #""text":"\#(escaped)"}}"#
        events.append(delta)
        events.append(#"{"type":"content_block_stop","index":\#(index)}"#)
        events.append(#"{"type":"message_delta","delta":{"stop_reason":"\#(stop)"},"usage":{"output_tokens":7}}"#)
        events.append(#"{"type":"message_stop"}"#)
        return sseLines(events)
    }

    private func badRequest(_ message: String) -> ScriptedStreamTransport.Reply {
        let line = #"{"type":"error","error":{"type":"invalid_request_error","message":"\#(message)"}}"#
        return .init(status: 400, lines: [line])
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theRequestCarriesTheKeyInItsHeaderAndTheRightVersion() async throws {
        let transport = ScriptedStreamTransport([.init(status: 200, lines: turn("Done."))])
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: { _ in })
        _ = try await client.send(request(search: true))
        let sent = try #require(transport.requests.first)
        #expect(sent.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "x-api-key") == anthropicKey)
        #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(sent.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(sent.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try body(sent)["model"] as? String == "claude-sonnet-5-5")
    }

    @Test func aFinishedTurnBecomesAResponsesResult() async throws {
        let reply = turn("Done.", sources: ["https://a.example/x"])
        let transport = ScriptedStreamTransport([.init(status: 200, lines: reply)])
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: { _ in })
        let result = try await client.send(request(search: true))
        #expect(result.text == "Done.")
        #expect(result.status == "completed")
        #expect(result.responseId == "msg_t")
        #expect(result.sourceURLs == ["https://a.example/x"])
        #expect(result.usage == ResponsesUsage(inputTokens: 10, outputTokens: 7, totalTokens: 17))
    }

    @Test func aRefusedKeyIsNamedButTheKeyIsNeverInTheError() async throws {
        let refused = ScriptedStreamTransport.Reply(status: 401, lines: [
            #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        ])
        let client = AnthropicClient(transport: ScriptedStreamTransport([refused]), apiKey: anthropicKey,
                                     sleep: { _ in })
        let error = await #expect(throws: ProviderError.self) { try await client.send(request()) }
        #expect(error == .keyRefused(provider: "Claude"))
        #expect(!String(describing: error).contains(anthropicKey))
    }

    @Test func rateLimitsAreRetriedAfterTenThenThirtySeconds() async throws {
        let limited = ScriptedStreamTransport.Reply(status: 429, lines: [])
        let transport = ScriptedStreamTransport([limited, limited, .init(status: 200, lines: turn("Later."))])
        let waits = SleepRecorder()
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: waits.sleep)
        #expect(try await client.send(request()).text == "Later.")
        #expect(waits.all == [.seconds(10), .seconds(30)])
        #expect(transport.requests.count == 3)
    }

    @Test func retryAfterReplacesTheScheduleAndIsCapped() async throws {
        let first = ScriptedStreamTransport.Reply(status: 429, headers: ["retry-after": "5"], lines: [])
        let second = ScriptedStreamTransport.Reply(status: 529, headers: ["retry-after": "90"], lines: [])
        let transport = ScriptedStreamTransport([first, second, .init(status: 200, lines: turn("Ok."))])
        let waits = SleepRecorder()
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: waits.sleep)
        _ = try await client.send(request())
        #expect(waits.all == [.seconds(5), .seconds(60)])
    }

    @Test func aServerThatStaysOverloadedGivesUpAfterTwoRetries() async throws {
        let overloaded = ScriptedStreamTransport.Reply(status: 529, lines: [])
        let transport = ScriptedStreamTransport([overloaded, overloaded, overloaded])
        let waits = SleepRecorder()
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: waits.sleep)
        let error = await #expect(throws: ProviderError.self) { try await client.send(request()) }
        #expect(error == .unavailable(provider: "Claude", status: 529))
        #expect(waits.all.count == 2)
        #expect(transport.requests.count == 3)
    }

    @Test func aRateLimitThatStaysIsReportedAsRateLimited() async throws {
        let limited = ScriptedStreamTransport.Reply(status: 429, lines: [])
        let client = AnthropicClient(transport: ScriptedStreamTransport([limited, limited, limited]),
                                     apiKey: anthropicKey, sleep: { _ in })
        let error = await #expect(throws: ProviderError.self) { try await client.send(request()) }
        #expect(error == .rateLimited(provider: "Claude"))
    }

    @Test func aSchemaRefusalIsRetriedOnceWithoutFormatAndTheJSONIsTakenFromTheText() async throws {
        let transport = ScriptedStreamTransport([
            badRequest("output_config.format is not supported with citations"),
            .init(status: 200, lines: turn("Here it is: {\"title\":\"A\"} thanks."))
        ])
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: { _ in })
        let result = try await client.send(request(search: true, withSchema: true))
        #expect(result.text == #"{"title":"A"}"#)

        let first = try body(try #require(transport.requests.first))
        #expect((first["output_config"] as? [String: Any])?["format"] != nil)
        let second = try body(try #require(transport.requests.last))
        #expect((second["output_config"] as? [String: Any])?["format"] == nil)
        let system = try #require(second["system"] as? String)
        #expect(system.contains("Reply with only one JSON object that matches this JSON Schema, with no other text:"))
        #expect(system.contains("\"title\""))
    }

    @Test func otherBadRequestsAreNotRetried() async throws {
        let transport = ScriptedStreamTransport([badRequest("max_tokens is too large")])
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: { _ in })
        let error = await #expect(throws: ProviderError.self) {
            try await client.send(request(search: true, withSchema: true))
        }
        #expect(error == .rejected(provider: "Claude", message: "max_tokens is too large"))
        #expect(transport.requests.count == 1)
    }

    @Test func pauseTurnSendsThePausedContentBackAndMergesTheSources() async throws {
        let transport = ScriptedStreamTransport([
            .init(status: 200, lines: turn("Searching.", stop: "pause_turn", sources: ["https://a.example/1"])),
            .init(status: 200, lines: turn("Final answer.", sources: ["https://b.example/2"]))
        ])
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: { _ in })
        let result = try await client.send(request(search: true))
        #expect(result.text == "Final answer.")
        #expect(result.sourceURLs == ["https://a.example/1", "https://b.example/2"])
        #expect(result.webSearchCount == 0)
        #expect(result.usage == ResponsesUsage(inputTokens: 20, outputTokens: 14, totalTokens: 34))

        let continued = try body(try #require(transport.requests.last))
        let messages = try #require(continued["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages.last?["role"] as? String == "assistant")
        #expect((messages.last?["content"] as? [Any])?.isEmpty == false)
    }

    @Test func pauseTurnStopsAfterThreeContinuations() async throws {
        let paused = turn("Still searching.", stop: "pause_turn")
        let transport = ScriptedStreamTransport([
            .init(status: 200, lines: paused), .init(status: 200, lines: paused),
            .init(status: 200, lines: paused), .init(status: 200, lines: paused)
        ])
        let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: { _ in })
        let error = await #expect(throws: ProviderError.self) { try await client.send(request(search: true)) }
        #expect(error == .stopped(provider: "Claude", reason: "pause_turn"))
        #expect(transport.requests.count == 4)

        // The paused turns go back as one assistant message, not one per turn.
        let last = try body(try #require(transport.requests.last))
        let messages = try #require(last["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant"])
        #expect((messages.last?["content"] as? [Any])?.count == 3)
    }

    @Test func aRefusalAndATokenLimitAreErrorsWithNoRetry() async throws {
        for reason in ["refusal", "max_tokens"] {
            let transport = ScriptedStreamTransport([.init(status: 200, lines: turn("No.", stop: reason))])
            let client = AnthropicClient(transport: transport, apiKey: anthropicKey, sleep: { _ in })
            let error = await #expect(throws: ProviderError.self) { try await client.send(request()) }
            #expect(error == .stopped(provider: "Claude", reason: reason))
            #expect(transport.requests.count == 1)
        }
    }

    @Test func anErrorEventInsideASuccessfulStreamIsAnError() async throws {
        let lines = sseLines([
            #"{"type":"message_start","message":{"id":"m","usage":{"input_tokens":1}}}"#,
            #"{"type":"error","error":{"type":"api_error","message":"Internal"}}"#
        ])
        let client = AnthropicClient(transport: ScriptedStreamTransport([.init(status: 200, lines: lines)]),
                                     apiKey: anthropicKey, sleep: { _ in })
        let error = await #expect(throws: ProviderError.self) { try await client.send(request()) }
        #expect(error == .streamFailed(provider: "Claude", type: "api_error"))
    }
}
