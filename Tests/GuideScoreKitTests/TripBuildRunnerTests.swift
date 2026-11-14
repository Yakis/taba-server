import Foundation
import GuideKit
@testable import GuideScoreKit
import Testing

/// A stand-in for the server: scripted answers to `POST /trips`, a list of states for each trip to report in turn,
/// and the guide for the trips that complete. Nothing goes over the network.
actor FakeTripServer: TripTransport {
    private var postAnswers: [TripResponse]
    private let pollStates: [String]
    private let guide: Data
    private var tripsStarted = 0
    private var statesLeft: [String: [String]] = [:]
    private(set) var calls: [String] = []
    private(set) var authorizations: Set<String> = []
    private(set) var activeTrips = 0
    private(set) var peakActiveTrips = 0

    init(postAnswers: [TripResponse] = [], pollStates: [String] = ["queued", "running", "completed"], guide: Data) {
        self.postAnswers = postAnswers
        self.pollStates = pollStates
        self.guide = guide
    }

    func send(_ request: URLRequest) async throws -> TripResponse {
        let path = request.url?.path ?? ""
        calls.append("\(request.httpMethod ?? "") \(path)")
        authorizations.insert(request.value(forHTTPHeaderField: "Authorization") ?? "")
        if request.httpMethod == "POST" {
            return post()
        }
        if path.hasSuffix("/guide") {
            activeTrips -= 1
            return TripResponse(status: 200, body: guide)
        }
        return poll(id: String(path.split(separator: "/").last ?? ""))
    }

    private func post() -> TripResponse {
        if !postAnswers.isEmpty {
            let answer = postAnswers.removeFirst()
            if answer.status != 202 {
                return answer
            }
        }
        tripsStarted += 1
        let id = "trip-\(tripsStarted)"
        statesLeft[id] = pollStates
        activeTrips += 1
        peakActiveTrips = max(peakActiveTrips, activeTrips)
        return TripResponse(status: 202, body: Data(#"{"id":"\#(id)","state":"queued","stage":"basics"}"#.utf8))
    }

    private func poll(id: String) -> TripResponse {
        var states = statesLeft[id] ?? []
        let state = states.count > 1 ? states.removeFirst() : (states.first ?? "failed")
        statesLeft[id] = states
        let body = #"{"id":"\#(id)","state":"\#(state)","stage":"plan","copyReviewRequired":false}"#
        return TripResponse(status: 200, body: Data(body.utf8))
    }
}

struct TripBuildRunnerTests {
    private static let token = "fake-token"
    private static let server = URL(string: "https://server.example.test")!
    private static let guide = Data(#"{"id":"fake"}"#.utf8)

    private func runner(_ fake: FakeTripServer, busyAttempts: Int = 40) -> TripBuildRunner {
        TripBuildRunner(server: Self.server, token: Self.token, transport: fake, pollInterval: .zero,
                        busyWait: .zero, maxBusyAttempts: busyAttempts)
    }

    private func request(_ name: String) -> ScenarioRequest {
        ScenarioRequest(name: name, body: Data("{}".utf8))
    }

    @Test func aBusyServerIsAskedAgainThenTheBuildIsSaved() async throws {
        let fake = FakeTripServer(postAnswers: [TripResponse(status: 503, body: Data())], guide: Self.guide)
        let folder = try makeFolder()
        let results = await runner(fake).build([request("one")], outFolder: folder, progress: { _ in })
        let result = try #require(results.first)
        #expect(result.state == "completed")
        #expect(result.tripId == "trip-1")
        let file = try #require(result.file)
        #expect(try Data(contentsOf: URL(filePath: file)) == Self.guide)
        #expect(result.problem == nil)
        #expect(await fake.calls == [
            "POST /trips", "POST /trips",
            "GET /trips/trip-1", "GET /trips/trip-1", "GET /trips/trip-1", "GET /trips/trip-1/guide"
        ])
    }

    @Test func everyRequestCarriesTheTokenAndTheTokenIsNeverReported() async throws {
        let fake = FakeTripServer(guide: Self.guide)
        let results = await runner(fake).build([request("one")], outFolder: try makeFolder(), progress: { _ in })
        #expect(await fake.authorizations == ["Bearer \(Self.token)"])
        #expect(results.allSatisfy { !($0.problem ?? "").contains(Self.token) })
    }

    @Test func aFailedBuildIsReportedAndNoGuideIsFetched() async throws {
        let fake = FakeTripServer(pollStates: ["running", "failed"], guide: Self.guide)
        let folder = try makeFolder()
        let results = await runner(fake).build([request("broken")], outFolder: folder, progress: { _ in })
        let result = try #require(results.first)
        #expect(result.state == "failed")
        #expect(result.file == nil)
        #expect(result.problem == "The build ended as failed.")
        #expect(!(await fake.calls).contains { $0.hasSuffix("/guide") })
    }

    @Test func aServerThatStaysBusyGivesUpWithItsStatus() async throws {
        let busy = [TripResponse](repeating: TripResponse(status: 503, body: Data()), count: 3)
        let fake = FakeTripServer(postAnswers: busy, guide: Self.guide)
        let results = await runner(fake, busyAttempts: 2).build([request("late")], outFolder: try makeFolder(),
                                                                progress: { _ in })
        let result = try #require(results.first)
        #expect(result.state == "error")
        #expect(result.problem == "The server answered 503 when asked to submit.")
        #expect(await fake.calls.count == 3)
    }

    @Test func noMoreThanTwoTripsRunAtOnce() async throws {
        let fake = FakeTripServer(pollStates: ["running", "completed"], guide: Self.guide)
        let requests = ["one", "two", "three", "four"].map(request)
        let results = await runner(fake).build(requests, outFolder: try makeFolder(), progress: { _ in })
        #expect(results.count == 4)
        #expect(results.allSatisfy { $0.file != nil })
        #expect(await fake.peakActiveTrips <= TripBuildRunner.maxConcurrent)
    }

    @Test func theCommandStopsBeforeAnyRequestWhenTheTokenIsNotSet() async throws {
        let folder = try makeFolder()
        let scenarios = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Evaluation/scenarios", directoryHint: .isDirectory)
        let arguments = ["build", "--server", "https://server.example.test", "--scenarios", scenarios.path,
                         "--out", folder.path]
        let status = await ScoreCLI.run(arguments, environment: [:])
        #expect(status == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func aResultLineNamesTheTripAndItsState() {
        let done = BuildResult(scenario: "one", tripId: "trip-1", state: "completed", buildMinutes: 9.5,
                               file: "/tmp/one.json", problem: nil)
        #expect(ScoreCLI.line(for: done) == "one: trip trip-1, completed, 9.5 min, saved to /tmp/one.json")
        let failed = BuildResult(scenario: "two", tripId: nil, state: "error", buildMinutes: nil, file: nil,
                                 problem: "Nope.")
        #expect(ScoreCLI.line(for: failed) == "two: no trip, error: Nope.")
    }
}
