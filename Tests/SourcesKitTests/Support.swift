import Foundation
import FoursquareKit
import GuideKit
import SourcesKit
import Synchronization

/// Answers each request from a closure and keeps the requests it saw. No network is used.
actor RecordingFetcher: HTTPFetching {
    private let answer: @Sendable (URLRequest) -> HTTPResponse
    private(set) var requests: [URLRequest] = []

    init(answer: @escaping @Sendable (URLRequest) -> HTTPResponse) {
        self.answer = answer
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return answer(request)
    }
}

/// Plays back a script: each request gets the next step, which is either a response or an error. A request with no
/// step left fails with `refused`, so an unexpected retry shows up in the test.
actor ScriptedFetcher: HTTPFetching {
    enum Step: Sendable {
        case respond(HTTPResponse)
        case fail(SourcesError)
    }

    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else {
            throw SourcesError.refused("the script has no step left")
        }
        switch steps.removeFirst() {
        case .respond(let response):
            return response
        case .fail(let error):
            throw error
        }
    }
}

/// Test helpers. JSON is written by hand from each API's documented shape, never copied from a live response.
enum Samples {
    static func response(_ json: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: Data(json.utf8), headers: [:])
    }

    static func places(_ json: String) throws -> [FoursquarePlace] {
        try JSONDecoder().decode(FoursquareSearchResponse.self, from: Data(json.utf8)).results
    }

    static func place(_ json: String) throws -> FoursquarePlace {
        try JSONDecoder().decode(FoursquarePlace.self, from: Data(json.utf8))
    }

    static func coordinate(_ latitude: Double, _ longitude: Double) -> Coordinate {
        guard let value = Coordinate(latitude: latitude, longitude: longitude) else {
            preconditionFailure("bad test coordinate")
        }
        return value
    }

    static func time(_ text: String) -> LocalTime {
        guard let value = LocalTime(text) else { preconditionFailure("bad test time \(text)") }
        return value
    }

    static func date(_ text: String) -> LocalDate {
        guard let value = LocalDate(text) else { preconditionFailure("bad test date \(text)") }
        return value
    }

    /// The query items of a request's URL, by name.
    static func query(_ request: URLRequest) -> [String: String] {
        let components = URLComponents(url: request.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)
        var result: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            result[item.name] = item.value
        }
        return result
    }
}

/// A clock and sleeper for tests. Sleeping moves the clock on, and each sleep is recorded.
final class FakeClock: Sendable {
    private let state: Mutex<(now: ContinuousClock.Instant, slept: [Duration])>

    init() {
        state = Mutex((now: ContinuousClock.now, slept: []))
    }

    var now: ContinuousClock.Instant {
        state.withLock { $0.now }
    }

    var sleeps: [Duration] {
        state.withLock { $0.slept }
    }

    func sleep(_ duration: Duration) {
        state.withLock { value in
            value.now = value.now.advanced(by: duration)
            value.slept.append(duration)
        }
    }
}

/// Foursquare place JSON for one hit, with the fields the tests vary.
enum HitJSON {
    static func place(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        category: String,
        categoryId: String = "4bf58dd8d48988d1c4941735",
        website: String? = nil,
        dateClosed: String? = nil
    ) -> String {
        var fields = [
            "\"fsq_place_id\":\"\(id)\"",
            "\"name\":\"\(name)\"",
            "\"latitude\":\(latitude)",
            "\"longitude\":\(longitude)",
            "\"location\":{\"address\":\"1 Example Row\",\"formatted_address\":\"1 Example Row, Edinburgh\"}",
            "\"categories\":[{\"fsq_category_id\":\"\(categoryId)\",\"name\":\"\(category)\"}]"
        ]
        if let website {
            fields.append("\"website\":\"\(website)\"")
        }
        if let dateClosed {
            fields.append("\"date_closed\":\"\(dateClosed)\"")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static func search(_ places: [String]) -> String {
        "{\"results\":[" + places.joined(separator: ",") + "]}"
    }
}
