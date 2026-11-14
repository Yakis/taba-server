import Foundation
import GuideKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What one scenario came to: its trip, the state the server ended in, and where its guide was saved.
public struct BuildResult: Sendable, Equatable {
    public let scenario: String
    public let tripId: String?
    public let state: String
    /// The server's build time in minutes, when the guide says; otherwise the time the runner waited.
    public let buildMinutes: Double?
    /// The file the guide was saved to, when it was.
    public let file: String?
    /// What went wrong, when something did. Never contains the token.
    public let problem: String?
}

/// Builds scenarios on a server and saves each guide: `POST /trips`, polling `GET /trips/:id`, then
/// `GET /trips/:id/guide`. At most `maxConcurrent` trips run at once, and a `503` (busy) is waited out.
public struct TripBuildRunner: Sendable {
    public static let maxConcurrent = 2
    /// The most polls before a build is given up on: an hour at the default 15-second interval.
    static let maxPolls = 240

    public let server: URL
    public let token: String
    public let transport: any TripTransport
    /// How long to wait between polls of a trip.
    public let pollInterval: Duration
    /// How long to wait before asking again when the server is busy.
    public let busyWait: Duration
    /// How many times a busy server is asked before a scenario is given up on.
    public let maxBusyAttempts: Int

    public init(server: URL, token: String, transport: any TripTransport = URLSessionTransport(),
                pollInterval: Duration = .seconds(15), busyWait: Duration = .seconds(15),
                maxBusyAttempts: Int = 40) {
        self.server = server
        self.token = token
        self.transport = transport
        self.pollInterval = pollInterval
        self.busyWait = busyWait
        self.maxBusyAttempts = maxBusyAttempts
    }

    /// Builds every request, at most `maxConcurrent` at a time, and saves each finished guide to `outFolder`.
    /// `progress` is called as each scenario ends, in the order they end.
    public func build(_ requests: [ScenarioRequest], outFolder: URL,
                      progress: @escaping @Sendable (BuildResult) -> Void) async -> [BuildResult] {
        var results: [BuildResult] = []
        await withTaskGroup(of: BuildResult.self) { group in
            var next = 0
            func enqueue() {
                let request = requests[next]
                next += 1
                group.addTask { await self.buildOne(request, outFolder: outFolder) }
            }
            while next < min(Self.maxConcurrent, requests.count) {
                enqueue()
            }
            for await result in group {
                progress(result)
                results.append(result)
                if next < requests.count {
                    enqueue()
                }
            }
        }
        return results
    }

    private func buildOne(_ request: ScenarioRequest, outFolder: URL) async -> BuildResult {
        let clock = ContinuousClock()
        let started = clock.now
        var tripId: String?
        do {
            let id = try await submit(request.body)
            tripId = id
            let state = try await waitUntilFinished(id)
            guard state == TripStateName.completed else {
                return BuildResult(scenario: request.name, tripId: id, state: state, buildMinutes: nil, file: nil,
                                   problem: "The build ended as \(state).")
            }
            let guide = try await fetchGuide(id)
            let file = outFolder.appending(path: "\(request.name).json")
            try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)
            try guide.write(to: file)
            let minutes = Self.serverMinutes(guide) ?? Self.minutes(started.duration(to: clock.now))
            return BuildResult(scenario: request.name, tripId: id, state: state, buildMinutes: minutes,
                               file: file.path, problem: nil)
        } catch {
            return BuildResult(scenario: request.name, tripId: tripId, state: "error", buildMinutes: nil, file: nil,
                               problem: String(describing: error))
        }
    }

    /// Posts the trip, waiting and retrying while the server is busy. Returns the new trip's id.
    private func submit(_ body: Data) async throws -> String {
        var busyAnswers = 0
        while true {
            let response = try await transport.send(request(method: "POST", path: ["trips"], body: body))
            switch response.status {
            case 202:
                return try decodeStatus(response.body).id
            case 503 where busyAnswers < maxBusyAttempts:
                busyAnswers += 1
                try await Task.sleep(for: busyWait)
            default:
                throw BuildError.unexpectedStatus(stage: "submit", status: response.status)
            }
        }
    }

    /// Polls the trip until it completed or failed, and returns that state.
    private func waitUntilFinished(_ id: String) async throws -> String {
        for _ in 0..<Self.maxPolls {
            let response = try await transport.send(request(method: "GET", path: ["trips", id]))
            guard response.status == 200 else {
                throw BuildError.unexpectedStatus(stage: "poll", status: response.status)
            }
            let state = try decodeStatus(response.body).state
            if state == TripStateName.completed || state == TripStateName.failed {
                return state
            }
            try await Task.sleep(for: pollInterval)
        }
        throw BuildError.tooManyPolls
    }

    private func fetchGuide(_ id: String) async throws -> Data {
        let response = try await transport.send(request(method: "GET", path: ["trips", id, "guide"]))
        guard response.status == 200 else {
            throw BuildError.unexpectedStatus(stage: "guide", status: response.status)
        }
        return response.body
    }

    private func request(method: String, path: [String], body: Data? = nil) -> URLRequest {
        var url = server
        for segment in path {
            url = url.appendingPathComponent(segment)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func decodeStatus(_ body: Data) throws -> TripStatusBody {
        do {
            return try JSONDecoder().decode(TripStatusBody.self, from: body)
        } catch {
            throw BuildError.badResponse
        }
    }

    /// The server's build time for a guide, in minutes, when the guide records one.
    static func serverMinutes(_ guide: Data) -> Double? {
        guard let built = try? GuideKit.jsonDecoder().decode(Guide.self, from: guide),
              let time = built.buildTime else { return nil }
        return Double(time.totalSeconds) / 60
    }

    static func minutes(_ duration: Duration) -> Double {
        Double(duration.components.seconds) / 60
    }
}

/// The trip states the server reports, as their names in JSON.
enum TripStateName {
    static let completed = "completed"
    static let failed = "failed"
}

/// The part of the server's trip status the runner reads.
struct TripStatusBody: Decodable {
    let id: String
    let state: String
}

/// What the server can say wrong about a build. None of these carries the token.
public enum BuildError: Error, Equatable, CustomStringConvertible {
    case unexpectedStatus(stage: String, status: Int)
    case badResponse
    case tooManyPolls

    public var description: String {
        switch self {
        case .unexpectedStatus(let stage, let status): "The server answered \(status) when asked to \(stage)."
        case .badResponse: "The server sent a response the runner could not read."
        case .tooManyPolls: "The build did not finish in the time allowed."
        }
    }
}

/// One scenario ready to send: its name and the request body with today's dates.
public struct ScenarioRequest: Sendable, Equatable {
    public let name: String
    public let body: Data

    public init(name: String, body: Data) {
        self.name = name
        self.body = body
    }
}
