import Foundation
import GuideKit
import SourcesKit
import Testing

// swiftlint:disable:next type_body_length
struct OverpassHoursSourceTests {
    private let checkedAt = Samples.date("2026-11-08")
    private let oink = HoursLookupTarget(
        placeId: "fsq:oink",
        name: "Oink",
        coordinate: Samples.coordinate(55.9510, -3.2010)
    )
    private let makars = HoursLookupTarget(
        placeId: "fsq:makars",
        name: "Makars Mash Bar",
        coordinate: Samples.coordinate(55.9460, -3.2140)
    )
    private let quiet = HoursLookupTarget(
        placeId: "fsq:quiet",
        name: "Quiet Cafe",
        coordinate: Samples.coordinate(55.9533, -3.1883)
    )
    private let firstEndpoint = URL(string: "https://first.example.com/api/interpreter")!
    private let secondEndpoint = URL(string: "https://second.example.com/api/interpreter")!
    private let thirdEndpoint = URL(string: "https://third.example.com/api/interpreter")!

    private var targets: [HoursLookupTarget] {
        [oink, makars, quiet]
    }

    /// Overpass elements in the shape `out tags center` returns for the filtered query. Nodes carry lat and lon. Ways
    /// carry a center. The way without hours and the far Oink are in the answer only to show they are not used.
    private let elementsJSON = """
    {"version":0.6,"generator":"Overpass API","elements":[
      {"type":"node","id":1001,"lat":55.95101,"lon":-3.20102,
       "tags":{"name":"Oink","opening_hours":"Mo-Su 12:00-21:00"}},
      {"type":"node","id":1003,"lat":55.95102,"lon":-3.20101,
       "tags":{"name":"Victoria Street"}},
      {"type":"node","id":1004,"lat":55.96000,"lon":-3.20100,
       "tags":{"name":"Oink","opening_hours":"Mo-Fr 10:00-11:00"}},
      {"type":"way","id":2002,"center":{"lat":55.94601,"lon":-3.21402},
       "tags":{"name":"Makars Mash Bar"}},
      {"type":"node","id":1005,"lat":55.94602,"lon":-3.21403,
       "tags":{"name":"Makars Mash Bar","opening_hours":"Mo-Su 16:00-24:00"}}
    ]}
    """

    private func success(_ json: String) -> ScriptedFetcher.Step {
        .respond(Samples.response(json))
    }

    private func status(_ code: Int) -> ScriptedFetcher.Step {
        .respond(Samples.response("", status: code))
    }

    /// Runs the source over `targets` with the scripted answers. Sleeps go to `clock`, which tests read when needed.
    private func lookup(
        _ steps: [ScriptedFetcher.Step],
        targets: [HoursLookupTarget]? = nil,
        endpoints: [URL] = [],
        batchSize: Int = 25,
        clock: FakeClock = FakeClock()
    ) async -> (OverpassLookup, ScriptedFetcher) {
        let fetcher = ScriptedFetcher(steps)
        let source = OverpassHoursSource(
            fetcher: fetcher,
            endpoints: endpoints,
            batchSize: batchSize,
            retryDelay: .seconds(10),
            sleep: { clock.sleep($0) }
        )
        let result = await source.hours(for: targets ?? self.targets, cityName: "Edinburgh", checkedAt: checkedAt)
        return (result, fetcher)
    }

    private func outcome(_ lookup: OverpassLookup, _ placeId: String) -> OSMHoursOutcome? {
        lookup.results.first { $0.placeId == placeId }?.outcome
    }

    private func body(of request: URLRequest) -> String {
        String(data: request.httpBody ?? Data(), encoding: .utf8)?.removingPercentEncoding ?? ""
    }

    // MARK: Matching

    @Test func aPlaceWithAnOpeningHoursObjectIsFound() async throws {
        let (result, _) = await lookup([success(elementsJSON)])
        guard case .found(let found) = outcome(result, "fsq:oink") else {
            Issue.record("Oink should be found")
            return
        }
        #expect(found.osmId == "node/1001")
        #expect(found.rawOpeningHours == "Mo-Su 12:00-21:00")
        #expect(found.reading.hours.hoursKnown)
        #expect(found.source.url == "https://www.openstreetmap.org/node/1001")
        #expect(found.source.id == "osm:node/1001")
        #expect(result.error == nil)
    }

    @Test func aPlaceWithNoMatchingObjectIsNotFound() async {
        let (result, _) = await lookup([success(elementsJSON)])
        #expect(outcome(result, "fsq:quiet") == .notFound)
    }

    @Test func aMatchingNameWithoutOpeningHoursIsNotUsed() async {
        let onlyWay = """
        {"elements":[{"type":"way","id":2002,"center":{"lat":55.94601,"lon":-3.21402},
                      "tags":{"name":"Makars Mash Bar"}}]}
        """
        let (result, _) = await lookup([success(onlyWay)], targets: [makars])
        #expect(outcome(result, "fsq:makars") == .notFound)
    }

    @Test func aMatchingObjectOutsideEightyMetresIsNotUsed() async {
        let onlyFar = """
        {"elements":[{"type":"node","id":1004,"lat":55.96000,"lon":-3.20100,
                      "tags":{"name":"Oink","opening_hours":"Mo-Fr 10:00-11:00"}}]}
        """
        let (result, _) = await lookup([success(onlyFar)], targets: [oink])
        #expect(outcome(result, "fsq:oink") == .notFound)
    }

    @Test func theResultsKeepTheTargetOrder() async {
        let (result, _) = await lookup([success(elementsJSON)])
        #expect(result.results.map(\.placeId) == ["fsq:oink", "fsq:makars", "fsq:quiet"])
    }

    // MARK: The query

    @Test func theQueryFiltersOnOpeningHoursWithAnAroundForEachPlace() async throws {
        let (_, fetcher) = await lookup([success(elementsJSON)])
        let request = try #require(await fetcher.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "overpass-api.de")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "TABA/0.1 (personal travel guide)")
        #expect(request.timeoutInterval == 120)
        let text = body(of: request)
        #expect(text.hasPrefix("data=[out:json][timeout:90];"))
        #expect(text.contains("nwr[\"opening_hours\"](around:80,55.951000,-3.201000);"))
        #expect(text.contains("nwr[\"opening_hours\"](around:80,55.946000,-3.214000);"))
        #expect(text.contains("out tags center;"))
    }

    @Test func targetsAreSentInBatchesOfTwentyFiveAndEachBatchIsOneRequest() async {
        let many = (0..<26).map { index in
            HoursLookupTarget(
                placeId: "fsq:\(index)",
                name: "Place \(index)",
                coordinate: Samples.coordinate(55.95, -3.19)
            )
        }
        let empty = success("{\"elements\":[]}")
        let (result, fetcher) = await lookup([empty, empty], targets: many)
        let requests = await fetcher.requests
        #expect(requests.count == 2)
        #expect(body(of: requests[0]).components(separatedBy: "nwr[").count - 1 == 25)
        #expect(body(of: requests[1]).components(separatedBy: "nwr[").count - 1 == 1)
        #expect(result.results.count == 26)
        #expect(result.error == nil)
    }

    @Test func aBatchSizeAboveTwentyFiveIsCappedAtTwentyFive() async {
        let many = (0..<26).map { index in
            HoursLookupTarget(
                placeId: "fsq:\(index)",
                name: "Place \(index)",
                coordinate: Samples.coordinate(55.95, -3.19)
            )
        }
        let empty = success("{\"elements\":[]}")
        let (_, fetcher) = await lookup([empty, empty], targets: many, batchSize: 100)
        #expect(await fetcher.requests.count == 2)
    }

    @Test func noTargetsSendsNothing() async {
        let (result, fetcher) = await lookup([], targets: [])
        #expect(result.results.isEmpty)
        #expect(result.error == nil)
        #expect(await fetcher.requests.isEmpty)
    }

    // MARK: Retries

    @Test func aGatewayTimeoutIsRetriedAfterTenSeconds() async {
        let clock = FakeClock()
        let (result, fetcher) = await lookup([status(504), success(elementsJSON)], clock: clock)
        #expect(await fetcher.requests.count == 2)
        #expect(clock.sleeps == [.seconds(10)])
        #expect(result.error == nil)
        guard case .found = outcome(result, "fsq:oink") else {
            Issue.record("Oink should be found on the retry")
            return
        }
    }

    @Test func aTooManyRequestsStatusIsRetried() async {
        let clock = FakeClock()
        let (result, fetcher) = await lookup([status(429), success(elementsJSON)], clock: clock)
        #expect(await fetcher.requests.count == 2)
        #expect(clock.sleeps == [.seconds(10)])
        #expect(result.error == nil)
    }

    @Test func aTimedOutRequestIsRetried() async {
        let (result, fetcher) = await lookup([.fail(.timedOut), success(elementsJSON)])
        #expect(await fetcher.requests.count == 2)
        #expect(result.error == nil)
        #expect(outcome(result, "fsq:makars") != nil)
    }

    @Test func aTimeoutReportedInTheRemarkIsRetried() async {
        let timedOut = #"{"elements":[],"remark":"runtime error: Query timed out in \"query\""}"#
        let clock = FakeClock()
        let (result, fetcher) = await lookup([success(timedOut), success(elementsJSON)], clock: clock)
        #expect(await fetcher.requests.count == 2)
        #expect(clock.sleeps == [.seconds(10)])
        #expect(result.error == nil)
    }

    @Test(arguments: [502, 503])
    func aBadGatewayOrAnUnavailableServerIsRetried(code: Int) async {
        let clock = FakeClock()
        let (result, fetcher) = await lookup([status(code), success(elementsJSON)], clock: clock)
        #expect(await fetcher.requests.count == 2)
        #expect(clock.sleeps == [.seconds(10)])
        #expect(result.error == nil)
    }

    @Test func aLostConnectionIsRetried() async {
        let clock = FakeClock()
        let (result, fetcher) = await lookup(
            [.fail(.network("connection lost")), success(elementsJSON)],
            clock: clock
        )
        #expect(await fetcher.requests.count == 2)
        #expect(clock.sleeps == [.seconds(10)])
        #expect(result.error == nil)
    }

    @Test func theEndpointsTakeTurnsAcrossTheAttempts() async {
        let (_, fetcher) = await lookup(
            [.fail(.timedOut), .fail(.timedOut), .fail(.timedOut), success(elementsJSON)],
            endpoints: [firstEndpoint, secondEndpoint, thirdEndpoint]
        )
        let hosts = await fetcher.requests.map { $0.url?.host ?? "" }
        #expect(hosts == ["first.example.com", "second.example.com", "third.example.com", "first.example.com"])
    }

    @Test func theDefaultEndpointsAreTheMainServerThenTheBackup() {
        #expect(OverpassHoursSource.defaultEndpoints.map(\.absoluteString) == [
            "https://overpass-api.de/api/interpreter",
            "https://overpass.kumi.systems/api/interpreter"
        ])
    }

    @Test func noEndpointsFallsBackToTheDefaults() async {
        let (_, fetcher) = await lookup([success(elementsJSON)], endpoints: [])
        #expect(await fetcher.requests.first?.url?.host == "overpass-api.de")
    }

    @Test func theRetryUsesTheNextEndpoint() async {
        let (_, fetcher) = await lookup(
            [.fail(.timedOut), success(elementsJSON)],
            endpoints: [firstEndpoint, secondEndpoint]
        )
        let requests = await fetcher.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.host == "first.example.com")
        #expect(requests[1].url?.host == "second.example.com")
    }

    @Test func otherServerErrorsAreNotRetried() async {
        let clock = FakeClock()
        let (result, fetcher) = await lookup([status(500)], clock: clock)
        #expect(await fetcher.requests.count == 1)
        #expect(clock.sleeps.isEmpty)
        #expect(result.error == .http(status: 500))
        #expect(result.results.allSatisfy { $0.outcome == .unavailable })
    }

    @Test func aServiceErrorInTheRemarkIsNotRetried() async {
        let failed = #"{"elements":[],"remark":"runtime error: Out of memory"}"#
        let (result, fetcher) = await lookup([success(failed)], targets: [oink])
        #expect(await fetcher.requests.count == 1)
        #expect(result.error != nil)
    }

    // MARK: Failure is reported, never thrown

    @Test func aBatchThatFailsEveryAttemptLeavesItsPlacesUnavailable() async {
        let clock = FakeClock()
        let (result, fetcher) = await lookup(Array(repeating: status(504), count: 4), clock: clock)
        #expect(await fetcher.requests.count == 4)
        #expect(clock.sleeps == [.seconds(10), .seconds(20), .seconds(40)])
        #expect(result.error == .http(status: 504))
        #expect(result.results.map(\.placeId) == ["fsq:oink", "fsq:makars", "fsq:quiet"])
        #expect(result.results.allSatisfy { $0.outcome == .unavailable })
    }

    @Test func aFailedBatchDoesNotStopTheBatchesAfterIt() async {
        // Twenty-eight targets make two batches: the first 25 fillers, then the three real places.
        let fillers = (0..<25).map { index in
            HoursLookupTarget(placeId: "fsq:f\(index)", name: "Filler \(index)", coordinate: Samples.coordinate(0, 0))
        }
        let (result, fetcher) = await lookup(
            Array(repeating: ScriptedFetcher.Step.fail(.network("connection lost")), count: 4)
                + [success(elementsJSON)],
            targets: fillers + targets
        )
        #expect(await fetcher.requests.count == 5)
        #expect(outcome(result, "fsq:f1") == .unavailable)
        guard case .found = outcome(result, "fsq:oink") else {
            Issue.record("Oink, in the batch after the failure, should still be found")
            return
        }
        #expect(outcome(result, "fsq:quiet") == .notFound)
        #expect(result.error == .network("connection lost"))
    }

    @Test func aRefusedRequestIsReportedWithoutThrowing() async {
        let (result, fetcher) = await lookup([])
        #expect(await fetcher.requests.count == 1)
        #expect(result.results.allSatisfy { $0.outcome == .unavailable })
        #expect(result.error != nil)
    }
}
