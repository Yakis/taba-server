import Foundation
@testable import LivePipelineKit
import ResponsesKit
import ServerKit
import Synchronization
import Testing

/// A clock the test moves by hand.
private final class TestClock: Sendable {
    private let state: Mutex<Date>

    init(_ start: Date) {
        state = Mutex(start)
    }

    var now: Date { state.withLock { $0 } }

    func advance(_ seconds: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// Answers each fetch with the next scripted reply, and counts the fetches.
private actor ScriptedFetch {
    private var replies: [Result<[String], any Error>]
    private(set) var calls = 0

    init(_ replies: [Result<[String], any Error>]) {
        self.replies = replies
    }

    func next() throws -> [String] {
        calls += 1
        guard !replies.isEmpty else { throw FakeFailure.offline }
        return try replies.removeFirst().get()
    }
}

private enum FakeFailure: Error { case offline }

/// Answers each request with the handler, and keeps the requests it saw.
private final class RecordingTransport: HTTPTransport, Sendable {
    private let handler: @Sendable (URLRequest) -> (Int, Data)
    private let seen = Mutex<[URLRequest]>([])

    init(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        self.handler = handler
    }

    var requests: [URLRequest] { seen.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        seen.withLock { $0.append(request) }
        let (status, body) = handler(request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            throw TransportError.notHTTP
        }
        return (body, response)
    }
}

struct ModelCatalogTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func cachesTheListForAnHourThenFetchesAgain() async {
        let clock = TestClock(start)
        let fetch = ScriptedFetch([.success(["gpt-6.1-sol"]), .success(["gpt-6.1-sol", "gpt-6.1-luna"])])
        let catalog = ModelCatalog(defaultModel: "gpt-6.1-sol", clock: { clock.now },
                                   fetchSlugs: { try await fetch.next() })
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol"])
        clock.advance(3599)
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol"])
        #expect(await fetch.calls == 1)
        clock.advance(2)
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol", "gpt-6.1-luna"])
        #expect(await fetch.calls == 2)
    }

    @Test func aFailedFetchKeepsTheLastGoodList() async {
        let clock = TestClock(start)
        let fetch = ScriptedFetch([.success(["gpt-6.1-sol", "gpt-6.1-terra"]), .failure(FakeFailure.offline)])
        let catalog = ModelCatalog(defaultModel: "gpt-6.1-sol", clock: { clock.now },
                                   fetchSlugs: { try await fetch.next() })
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol", "gpt-6.1-terra"])
        clock.advance(3601)
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol", "gpt-6.1-terra"])
        #expect(await fetch.calls == 2)
    }

    @Test func withNoGoodListOnlyTheDefaultIsOffered() async {
        let fetch = ScriptedFetch([])
        let catalog = ModelCatalog(defaultModel: "gpt-6.1-terra", clock: { self.start },
                                   fetchSlugs: { try await fetch.next() })
        #expect(await catalog.options() == [ModelOption(id: "gpt-6.1-terra", name: "Terra")])
        let unnamed = ModelCatalog(defaultModel: "gpt-4o", clock: { self.start },
                                   fetchSlugs: { try await fetch.next() })
        #expect(await unnamed.options() == [ModelOption(id: "gpt-4o", name: "gpt-4o")])
    }

    @Test func theDefaultIsAlwaysOfferedFirstWhenTheAccountListLacksIt() async {
        let fetch = ScriptedFetch([.success(["gpt-6.1-terra", "gpt-6.1-luna"])])
        let catalog = ModelCatalog(defaultModel: "gpt-6.1-sol", clock: { self.start },
                                   fetchSlugs: { try await fetch.next() })
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol", "gpt-6.1-terra", "gpt-6.1-luna"])
    }

    @Test func theDefaultTakesThePlaceOfItsFamilysOtherVersion() async {
        let fetch = ScriptedFetch([.success(["gpt-6-sol", "gpt-6.1-terra"])])
        let catalog = ModelCatalog(defaultModel: "gpt-6.1-sol", clock: { self.start },
                                   fetchSlugs: { try await fetch.next() })
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol", "gpt-6.1-terra"])
    }

    @Test func theDefaultKeepsItsPlaceWhenTheAccountListHasIt() async {
        let fetch = ScriptedFetch([.success(["gpt-6.1-sol", "gpt-6.1-terra", "gpt-6.1-luna"])])
        let catalog = ModelCatalog(defaultModel: "gpt-6.1-terra", clock: { self.start },
                                   fetchSlugs: { try await fetch.next() })
        #expect(await catalog.options().map(\.id) == ["gpt-6.1-sol", "gpt-6.1-terra", "gpt-6.1-luna"])
    }

    @Test func refreshesTheTokenOnceWhenThePlanRefusesIt() async throws {
        let transport = RecordingTransport { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer stale-token-not-real"
                ? (401, Data())
                : (200, Data(#"{"models":[{"slug":"gpt-6.1-sol"}]}"#.utf8))
        }
        let fetch = ModelsFetch(client: ModelsClient(transport: transport)) { forceRefresh in
            forceRefresh ? "fresh-token-not-real" : "stale-token-not-real"
        }
        #expect(try await fetch.slugs() == ["gpt-6.1-sol"])
        #expect(transport.requests.count == 2)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization")
            == "Bearer fresh-token-not-real")
    }

    @Test func otherFailuresAreNotRetried() async {
        let transport = RecordingTransport { _ in (500, Data()) }
        let fetch = ModelsFetch(client: ModelsClient(transport: transport)) { _ in "token-not-real" }
        await #expect(throws: ModelsClientError.http(status: 500)) {
            try await fetch.slugs()
        }
        #expect(transport.requests.count == 1)
    }
}
