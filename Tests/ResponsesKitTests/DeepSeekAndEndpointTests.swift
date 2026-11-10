import Foundation
@testable import ResponsesKit
import Testing

struct DeepSeekAndEndpointTests {
    /// A search answer in the Responses format with no `action.sources`, as DeepSeek sends it.
    private static let searchStream = sseLines([
        #"{"type":"response.output_item.done","item":{"type":"web_search_call","id":"ws_1","#
            + #""action":{"type":"search","query":"Edinburgh markets"},"#
            + #""results":[{"url":"https://edinburgh.example/markets"},{"url":"https://example.org/night"}]}}"#,
        #"{"type":"response.output_text.delta","delta":"Markets run on Sundays."}"#,
        #"{"type":"response.output_item.done","item":{"type":"message","id":"msg_1","content":[{"type":"output_text","#
            + #""text":"Markets run on Sundays.","annotations":[{"type":"url_citation","#
            + #""url":"https://edinburgh.example/markets","title":"Markets"}]}]}}"#,
        #"{"type":"response.completed","response":{"id":"resp_d","status":"completed","#
            + #""output":[{"type":"web_search_call","id":"ws_1"}],"#
            + #""usage":{"input_tokens":9,"output_tokens":4,"total_tokens":13}}}"#
    ])

    private func send(_ endpoint: ResponsesEndpoint,
                      lines: [String]) async -> (ResponsesOutcome, ScriptedStreamTransport) {
        let transport = ScriptedStreamTransport([.init(status: 200, lines: lines)])
        let client = ResponsesClient(transport: transport, endpoint: endpoint)
        let outcome = await client.send(body: Data("{}".utf8), accessToken: "deepseek-key-not-real-0001")
        return (outcome, transport)
    }

    @Test func deepSeekGoesToItsOwnURLWithTheKeyAsBearerAndNoChatGPTHeaders() async throws {
        let (_, transport) = await send(.deepSeek, lines: Self.searchStream)
        let sent = try #require(transport.requests.first)
        #expect(sent.url?.absoluteString == "https://api.deepseek.com/responses")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-key-not-real-0001")
        let names = Set(sent.allHTTPHeaderFields?.keys.map { $0 } ?? [])
        #expect(names == ["Authorization", "Content-Type", "Accept"])
    }

    @Test func theChatGPTDefaultIsUnchanged() async throws {
        let (_, transport) = await send(.chatGPT, lines: Self.searchStream)
        let sent = try #require(transport.requests.first)
        #expect(sent.url?.absoluteString == ResponsesClient.endpoint)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-key-not-real-0001")
    }

    @Test func aDeepSeekSearchWithoutSourcesUsesTheCitationAndSearchURLs() async throws {
        let (outcome, _) = await send(.deepSeek, lines: Self.searchStream)
        let result = try #require(outcome.result)
        #expect(result.webSearchCount == 1)
        #expect(result.sourceURLs == ["https://edinburgh.example/markets", "https://example.org/night"])
        #expect(result.citationURLs == ["https://edinburgh.example/markets"])
        #expect(result.text == "Markets run on Sundays.")
    }

    @Test func theChatGPTRouteDoesNotRecoverSources() async throws {
        let (outcome, _) = await send(.chatGPT, lines: Self.searchStream)
        let result = try #require(outcome.result)
        #expect(result.sourceURLs.isEmpty)
        #expect(result.citationURLs == ["https://edinburgh.example/markets"])
    }

    @Test func realSourcesAreKeptAndNotReplacedByRecovery() async throws {
        let lines = sseLines([
            #"{"type":"response.output_item.done","item":{"type":"web_search_call","id":"ws_2","#
                + #""action":{"type":"search","sources":[{"type":"url","url":"https://real.example/one"}]}}}"#,
            #"{"type":"response.completed","response":{"id":"resp_e","status":"completed","output":[]}}"#
        ])
        let (outcome, _) = await send(.deepSeek, lines: lines)
        #expect(try #require(outcome.result).sourceURLs == ["https://real.example/one"])
    }

    @Test func recoveryKeepsOnlyWebAddressesWithoutRepeats() {
        #expect(SourceRecovery.urls(
            citations: ["https://a.example/x", "https://a.example/x", "ftp://not-web.example/y"],
            searchItemURLs: ["https://b.example/y", "https://b.example/y", "not a url"]
        ) == ["https://a.example/x", "https://b.example/y"])
        let item: JSONValue = .object([
            "query": .string("https://not-a-url-field.example but a query"),
            "results": .array([.object(["link": .string("http://c.example/z")])]),
            "count": .integer(3)
        ])
        // A string with a space in it is not an address, so only the link is kept.
        #expect(SourceRecovery.webURLs(in: item) == ["http://c.example/z"])
    }

    @Test func aRequestCanBeSentToAnotherModelIdWithEverythingElseKept() throws {
        let request = ResponsesRequest(model: "deepseek-flash", instructions: "i", userText: "u",
                                       webSearch: true, includeSearchSources: true, reasoningEffort: "low")
        let moved = request.replacingModel("deepseek-v4-pro")
        #expect(moved.model == "deepseek-v4-pro")
        #expect(moved.webSearch && moved.includeSearchSources)
        #expect(moved.reasoningEffort == "low")
        #expect(moved.messages == request.messages)
    }

    @Test func aFailedOutcomeMapsToTheSameProviderErrors() {
        func error(_ status: Int) -> ProviderError {
            let outcome = ResponsesOutcome(result: nil, error: nil, rawBody: "", status: status)
            return ProviderError.from(outcome, provider: "DeepSeek")
        }
        #expect(error(401) == .keyRefused(provider: "DeepSeek"))
        #expect(error(403) == .keyRefused(provider: "DeepSeek"))
        #expect(error(429) == .rateLimited(provider: "DeepSeek"))
        #expect(error(503) == .unavailable(provider: "DeepSeek", status: 503))
        #expect(error(400) == .requestFailed(provider: "DeepSeek", status: 400))
    }
}
