import Foundation
import SourcesKit
import Testing

struct HTTPSeamTests {
    @Test func headersAreFoundWhateverTheCaseTheServerUsed() {
        let response = HTTPResponse(status: 200, body: Data(), headers: ["Content-Type": "application/json"])
        #expect(response.header("content-type") == "application/json")
        #expect(response.header("CONTENT-TYPE") == "application/json")
        #expect(response.headers["content-type"] == "application/json")
    }

    @Test func onlyTwoHundredRangeStatusesAreSuccess() {
        #expect(HTTPResponse(status: 204, body: Data(), headers: [:]).isSuccess)
        #expect(!HTTPResponse(status: 404, body: Data(), headers: [:]).isSuccess)
        #expect(!HTTPResponse(status: 199, body: Data(), headers: [:]).isSuccess)
    }

    @Test func aCappedFetcherSendsUpToItsLimitAndThenRefuses() async throws {
        let inner = RecordingFetcher { _ in HTTPResponse(status: 200, body: Data(), headers: [:]) }
        let capped = CappedFetcher(inner: inner, limit: 2)
        let request = URLRequest(url: try #require(URL(string: "https://example.com/")))
        _ = try await capped.send(request)
        _ = try await capped.send(request)
        await #expect(throws: SourcesError.self) {
            try await capped.send(request)
        }
        #expect(await capped.sentCount == 2)
        #expect(await inner.requests.count == 2)
    }

    @Test func aPacerWaitsOneIntervalBetweenSlots() async throws {
        let clock = FakeClock()
        let pacer = RequestPacer(
            interval: .milliseconds(500),
            now: { clock.now },
            sleep: { clock.sleep($0) }
        )
        try await pacer.wait()
        try await pacer.wait()
        try await pacer.wait()
        #expect(clock.sleeps == [.milliseconds(500), .milliseconds(500)])
    }

    @Test func aPacerDoesNotWaitWhenEnoughTimeHasPassed() async throws {
        let clock = FakeClock()
        let pacer = RequestPacer(
            interval: .seconds(1),
            now: { clock.now },
            sleep: { clock.sleep($0) }
        )
        try await pacer.wait()
        clock.sleep(.seconds(5))
        try await pacer.wait()
        #expect(clock.sleeps == [.seconds(5)])
    }
}
