import Foundation
import ResponsesKit
import Testing

struct RequestBodyTests {
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func bodyIsStoreFalseStreamTrueWithInstructionsAndNoSystemItem() throws {
        let request = ResponsesRequest(
            model: "test-model", instructions: "Reply with one word.", userText: "Say hello."
        )
        let body = try object(try request.body())
        #expect(body["store"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
        #expect(body["instructions"] as? String == "Reply with one word.")
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input.first?["role"] as? String == "user")
        #expect(!input.contains { $0["role"] as? String == "system" })
    }

    @Test func rejectedParametersAreNeverSent() throws {
        let request = ResponsesRequest(
            model: "test-model",
            instructions: "x",
            userText: "y",
            structuredOutput: ProbeSchemas.research,
            webSearch: true,
            includeSearchSources: true,
            reasoningEffort: "low"
        )
        let body = try object(try request.body())
        for name in ResponsesRequest.rejectedParameters {
            #expect(body[name] == nil, "\(name) must not be sent")
        }
    }

    @Test func structuredOutputIsAStrictJSONSchema() throws {
        let request = ResponsesRequest(
            model: "test-model",
            instructions: "x",
            userText: "y",
            structuredOutput: ProbeSchemas.research
        )
        let body = try object(try request.body())
        let text = try #require(body["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
        #expect(format["name"] as? String == "research_result")
    }

    @Test func webSearchAndSourcesAreOptIn() throws {
        let plain = try object(try ResponsesRequest(model: "m", instructions: "i", userText: "u").body())
        #expect(plain["tools"] == nil)
        #expect(plain["include"] == nil)

        let search = try object(try ResponsesRequest(
            model: "m", instructions: "i", userText: "u", webSearch: true, includeSearchSources: true
        ).body())
        let tools = try #require(search["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "web_search")
        #expect(search["include"] as? [String] == ["web_search_call.action.sources"])
    }

    @Test func theRejectedParameterCheckAddsOnlyTheNamedField() throws {
        let request = ResponsesRequest(model: "m", instructions: "i", userText: "u")
        let body = try object(try request.body(addingRejectedParameter: "temperature", value: .number(0.2)))
        #expect(body["temperature"] as? Double == 0.2)
        #expect(body["store"] as? Bool == false)
    }
}

struct SSEParserTests {
    @Test func readsEventsSeparatedByBlankLines() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        let lines = [
            "event: response.output_text.delta", "data: {\"delta\":\"Hi\"}", "", ": a comment", "data: one",
            "data: two", ""
        ]
        for line in lines {
            if let event = parser.consume(line: line) { events.append(event) }
        }
        #expect(events == [
            SSEEvent(name: "response.output_text.delta", data: "{\"delta\":\"Hi\"}"),
            SSEEvent(name: nil, data: "one\ntwo")
        ])
    }

    @Test func flushesAnEventAtEndOfStream() {
        var parser = SSEParser()
        _ = parser.consume(line: "data: last")
        #expect(parser.finish() == SSEEvent(name: nil, data: "last"))
    }
}

struct ResponsesStreamTests {
    private static let textStream = [
        "event: response.created",
        "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\",\"status\":\"in_progress\"}}",
        "",
        "event: response.output_text.delta",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hel\"}",
        "",
        "event: response.output_text.delta",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"lo\"}",
        "",
        "event: response.completed",
        "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\","
            + "\"output\":[],\"usage\":{\"input_tokens\":10,\"output_tokens\":2,\"total_tokens\":12}}}",
        ""
    ]

    private static let searchStream = [
        "data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"web_search_call\",\"id\":\"ws_1\","
            + "\"status\":\"completed\",\"action\":{\"type\":\"search\",\"query\":\"Stockbridge Market\","
            + "\"sources\":[{\"type\":\"url\",\"url\":\"https://edinburgh.org/things-to-do/markets/\"},"
            + "{\"type\":\"url\",\"url\":\"https://example.com/other\"}]}}}",
        "",
        "data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"message\",\"id\":\"msg_1\","
            + "\"content\":[{\"type\":\"output_text\",\"text\":\"Markets on Sundays.\",\"annotations\":["
            + "{\"type\":\"url_citation\",\"url\":\"https://edinburgh.org/things-to-do/markets/\","
            + "\"title\":\"Markets\"}"
            + "]}]}}",
        "",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Markets on Sundays.\"}",
        "",
        "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_2\",\"status\":\"completed\","
            + "\"output\":[{\"type\":\"web_search_call\",\"id\":\"ws_1\"}],\"usage\":{\"input_tokens\":100,"
            + "\"output_tokens\":20,\"total_tokens\":120}}}",
        ""
    ]

    private func send(_ lines: [String], status: Int = 200) async -> ResponsesOutcome {
        let client = ResponsesClient(transport: FakeStreamTransport(status: status, lines: lines))
        return await client.send(body: Data("{}".utf8), accessToken: "access-token-fake-0001")
    }

    @Test func textDeltasAndCompletionGiveTheAnswer() async throws {
        let outcome = await send(Self.textStream)
        let result = try #require(outcome.result)
        #expect(result.text == "Hello")
        #expect(result.status == "completed")
        #expect(result.responseId == "resp_1")
        #expect(result.usage == ResponsesUsage(inputTokens: 10, outputTokens: 2, totalTokens: 12))
        #expect(outcome.error == nil)
        #expect(outcome.rawBody.contains("response.completed"))
    }

    @Test func webSearchSourcesAndCitationsComeBack() async throws {
        let outcome = await send(Self.searchStream)
        let result = try #require(outcome.result)
        #expect(result.webSearchCount == 1)
        #expect(result.sourceURLs == ["https://edinburgh.org/things-to-do/markets/", "https://example.com/other"])
        #expect(result.citationURLs == ["https://edinburgh.org/things-to-do/markets/"])
        #expect(result.text == "Markets on Sundays.")
    }

    @Test func usageLimitInTheStreamGetsItsOwnCase() async {
        let lines = [
            "data: {\"type\":\"response.failed\",\"response\":{\"id\":\"resp_3\",\"status\":\"failed\","
                + "\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\","
                + "\"message\":\"Usage limit reached for this app.\"}}}",
            ""
        ]
        let outcome = await send(lines)
        #expect(outcome.error == .usageLimitExceeded(message: "Usage limit reached for this app."))
        #expect(outcome.result == nil)
    }

    @Test func usageUnavailableInTheStreamGetsItsOwnCase() async {
        let lines = [
            "data: {\"type\":\"response.failed\",\"response\":{\"error\":{"
                + "\"code\":\"subscription_sharing_usage_unavailable\",\"message\":\"Try later.\"}}}",
            ""
        ]
        let outcome = await send(lines)
        #expect(outcome.error == .usageUnavailable(message: "Try later."))
    }

    @Test func usageLimitOverHTTPGetsItsOwnCase() async {
        let body = "{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\",\"message\":\"Limit.\"}}"
        let outcome = await send([body], status: 429)
        #expect(outcome.error == .usageLimitExceeded(message: "Limit."))
        #expect(outcome.status == 429)
    }

    @Test func otherStructuredCodesKeepTheirCodeAndParam() async {
        let body = "{\"error\":{\"code\":\"subscription_sharing_unsupported_capability\","
            + "\"param\":\"tools\",\"message\":\"Not supported.\"}}"
        let outcome = await send([body], status: 400)
        #expect(outcome.error == .apiError(
            code: "subscription_sharing_unsupported_capability",
            param: "tools",
            message: "Not supported.",
            status: 400
        ))
    }

    @Test func admissionRefusalKeepsTheDetailText() async {
        let outcome = await send(["{\"detail\":\"Direct routing is unavailable.\"}"], status: 503)
        #expect(outcome.error == .admissionRejected(status: 503, detail: "Direct routing is unavailable."))
    }

    @Test func aStreamWithoutCompletionIsNotASuccess() async {
        let lines = ["data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}", ""]
        let outcome = await send(lines)
        #expect(outcome.result == nil)
        #expect(outcome.error == .streamEndedWithoutCompletion)
    }

    @Test func incompleteResponseIsReported() async {
        let event = "data: {\"type\":\"response.incomplete\","
            + "\"response\":{\"incomplete_details\":{\"reason\":\"max_tokens\"}}}"
        let lines = [event, ""]
        let outcome = await send(lines)
        #expect(outcome.error == .incomplete(reason: "max_tokens"))
    }
}
