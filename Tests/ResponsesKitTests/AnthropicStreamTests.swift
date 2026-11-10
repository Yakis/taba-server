import Foundation
@testable import ResponsesKit
import Testing

struct AnthropicStreamTests {
    private static let searchTurn = sseLines([
        #"{"type":"message_start","message":{"id":"msg_01","usage":{"input_tokens":120,"output_tokens":1}}}"#,
        #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":"","citations":null}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me search."}}"#,
        #"{"type":"content_block_stop","index":0}"#,
        #"{"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","#
            + #""id":"srv_1","name":"web_search","input":{}}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","#
            + #""partial_json":"{\"query\":"}}"#,
        #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","#
            + #""partial_json":" \"Edinburgh markets\"}"}}"#,
        #"{"type":"content_block_stop","index":1}"#,
        #"{"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","#
            + #""tool_use_id":"srv_1","content":[{"type":"web_search_result","#
            + #""url":"https://edinburgh.example/markets","title":"Markets","page_age":"2d","#
            + #""encrypted_content":"abc"},{"type":"web_search_result","#
            + #""url":"https://example.org/night","title":"Night","encrypted_content":"def"}]}}"#,
        #"{"type":"content_block_stop","index":2}"#,
        #"{"type":"content_block_start","index":3,"content_block":{"type":"text","text":"","citations":[]}}"#,
        #"{"type":"content_block_delta","index":3,"delta":{"type":"text_delta","#
            + #""text":"Markets run on Sundays."}}"#,
        #"{"type":"content_block_delta","index":3,"delta":{"type":"citations_delta","#
            + #""citation":{"type":"web_search_result_location","#
            + #""url":"https://edinburgh.example/markets","title":"Markets","cited_text":"Sundays"}}}"#,
        #"{"type":"content_block_stop","index":3}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"#
            + #""usage":{"output_tokens":42,"server_tool_use":{"web_search_requests":1}}}"#,
        #"{"type":"message_stop"}"#
    ])

    @Test func theAnswerIsTheTextAfterTheLastSearch() throws {
        let turn = try AnthropicStream.turn(lines: Self.searchTurn)
        #expect(turn.answer == "Markets run on Sundays.")
        #expect(turn.messageID == "msg_01")
        #expect(turn.stopReason == "end_turn")
    }

    @Test func sourcesCitationsAndUsageAreRead() throws {
        let turn = try AnthropicStream.turn(lines: Self.searchTurn)
        #expect(turn.sourceURLs == ["https://edinburgh.example/markets", "https://example.org/night"])
        #expect(turn.citationURLs == ["https://edinburgh.example/markets"])
        #expect(turn.inputTokens == 120)
        #expect(turn.outputTokens == 42)
        #expect(turn.webSearchRequests == 1)
    }

    @Test func theContentIsRebuiltAsItWasSent() throws {
        let turn = try AnthropicStream.turn(lines: Self.searchTurn)
        #expect(turn.content.count == 4)
        let tool = try #require(turn.content[1].objectValue)
        #expect(tool["type"] == .string("server_tool_use"))
        #expect(tool["input"] == .object(["query": .string("Edinburgh markets")]))
        let answer = try #require(turn.content[3].objectValue)
        #expect(answer["text"] == .string("Markets run on Sundays."))
        #expect(answer["citations"]?.arrayValue?.count == 1)
        // Text with no citations keeps no citations key, which the API would otherwise reject as empty.
        let narration = try #require(turn.content[0].objectValue)
        #expect(narration["citations"] == nil)
    }

    @Test func aPauseTurnKeepsItsStopReasonForTheCaller() throws {
        let lines = Self.searchTurn.map { $0.replacingOccurrences(of: "end_turn", with: "pause_turn") }
        let turn = try AnthropicStream.turn(lines: lines)
        #expect(turn.stopReason == "pause_turn")
    }

    @Test func aRefusalIsReadButIsNotAnAnswerForTheCaller() throws {
        let lines = sseLines([
            #"{"type":"message_start","message":{"id":"msg_2","usage":{"input_tokens":5,"output_tokens":0}}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":0}}"#,
            #"{"type":"message_stop"}"#
        ])
        let turn = try AnthropicStream.turn(lines: lines)
        #expect(turn.stopReason == "refusal")
        #expect(turn.answer == "")
    }

    @Test func withNoSearchAllTheTextIsTheAnswer() throws {
        let lines = sseLines([
            #"{"type":"message_start","message":{"id":"msg_3","usage":{"input_tokens":5}}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello "}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"there."}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#,
            #"{"type":"message_stop"}"#
        ])
        let turn = try AnthropicStream.turn(lines: lines)
        #expect(turn.answer == "Hello there.")
        #expect(turn.webSearchRequests == 0)
        #expect(turn.sourceURLs.isEmpty)
    }

    @Test func anErrorEventThrowsWithItsType() {
        let lines = sseLines([
            #"{"type":"message_start","message":{"id":"msg_4","usage":{"input_tokens":5}}}"#,
            #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        ])
        #expect(throws: ProviderError.streamFailed(provider: "Claude", type: "overloaded_error")) {
            try AnthropicStream.turn(lines: lines)
        }
    }

    @Test func aStreamWithoutAStopReasonIsMalformed() {
        let lines = sseLines([
            #"{"type":"message_start","message":{"id":"msg_5","usage":{"input_tokens":5}}}"#,
            #"{"type":"message_stop"}"#
        ])
        #expect(throws: ProviderError.malformedResponse(provider: "Claude")) {
            try AnthropicStream.turn(lines: lines)
        }
    }

    @Test func aBrokenToolInputIsMalformed() {
        let lines = sseLines([
            #"{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","#
                + #""id":"s","name":"web_search","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","#
                + #""partial_json":"{\"query\":"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}"#
        ])
        #expect(throws: ProviderError.malformedResponse(provider: "Claude")) {
            try AnthropicStream.turn(lines: lines)
        }
    }

    @Test func aRefusedRequestBodyGivesItsErrorDetails() {
        let body = [#"{"type":"error","error":{"type":"invalid_request_error","message":"Bad format."}}"#]
        let details = AnthropicStream.errorDetails(lines: body)
        #expect(details.type == "invalid_request_error")
        #expect(details.message == "Bad format.")
        #expect(AnthropicStream.errorDetails(lines: ["not json"]).message == nil)
    }
}
