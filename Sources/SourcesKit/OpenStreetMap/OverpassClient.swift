import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoursquareKit
import GuideKit

/// Sends one Overpass query and decodes its elements. Both OpenStreetMap sources use it.
///
/// The query goes to the endpoints in turn, one per attempt, so the endpoints take turns. A failure worth another
/// try (a timeout, a lost connection, or a 429, 502, 503 or 504) is retried, up to `attempts` attempts in all, with
/// waits of `retryDelay`, then twice that, then four times that. Any other failure is not retried. Nothing throws: the
/// result is a `Result`.
struct OverpassClient: Sendable {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// Attempts per query for the hours lookup: the first try and three retries.
    static let defaultAttempts = 4

    private let fetcher: any HTTPFetching
    private let endpoints: [URL]
    private let timeoutSeconds: Int
    private let retryDelay: Duration
    private let attempts: Int
    private let sleep: Sleep

    /// - Parameters:
    ///   - endpoints: Tried in rotation. Empty falls back to `OverpassHoursSource.defaultEndpoints`.
    ///   - timeoutSeconds: The `[timeout:]` the queries are written with. The request waits 30 seconds longer.
    ///   - retryDelay: The wait before the first retry. Each later retry waits twice as long as the one before.
    ///   - attempts: The most tries for one query, the first included. At least one.
    ///   - sleep: Injected so tests do not wait.
    init(
        fetcher: any HTTPFetching,
        endpoints: [URL],
        timeoutSeconds: Int,
        retryDelay: Duration,
        attempts: Int = OverpassClient.defaultAttempts,
        sleep: @escaping Sleep
    ) {
        self.fetcher = fetcher
        self.endpoints = endpoints.isEmpty ? OverpassHoursSource.defaultEndpoints : endpoints
        self.timeoutSeconds = timeoutSeconds
        self.retryDelay = retryDelay
        self.attempts = max(attempts, 1)
        self.sleep = sleep
    }

    /// Runs one query, with its permitted retries, and returns the elements of the answer.
    func run(_ query: String) async -> Result<[OverpassElement], SourcesError> {
        var lastError = SourcesError.refused("no attempt was made")
        for attempt in 0..<attempts {
            let url = endpoints[attempt % endpoints.count]
            switch await send(query: query, to: url) {
            case .success(let elements):
                return .success(elements)
            case .failure(let error):
                lastError = error
                guard attempt + 1 < attempts, Self.isRetryable(error) else {
                    return .failure(error)
                }
                do {
                    // After attempt 0 this is retryDelay, after attempt 1 twice that, after attempt 2 four times that.
                    try await sleep(retryDelay * (1 << attempt))
                } catch {
                    return .failure(lastError)
                }
            }
        }
        return .failure(lastError)
    }

    /// Failures worth another attempt: a timeout, a lost connection, or an overloaded server (429, 502, 503, 504).
    static func isRetryable(_ error: SourcesError) -> Bool {
        switch error {
        case .timedOut, .network:
            return true
        case .http(status: 429), .http(status: 502), .http(status: 503), .http(status: 504):
            return true
        default:
            return false
        }
    }

    private func send(query: String, to url: URL) async -> Result<[OverpassElement], SourcesError> {
        let response: HTTPResponse
        do {
            response = try await fetcher.send(request(for: query, url: url))
        } catch let error as SourcesError {
            return .failure(error)
        } catch {
            return .failure(.network(String(describing: error)))
        }
        guard response.isSuccess else {
            return .failure(.http(status: response.status))
        }
        let decoded: OverpassResponse
        do {
            decoded = try JSONDecoder().decode(OverpassResponse.self, from: response.body)
        } catch {
            return .failure(.malformed("the Overpass response"))
        }
        if let remark = decoded.remark, remark.lowercased().contains("error") {
            let timedOut = remark.lowercased().contains("timed out")
            return .failure(timedOut ? .timedOut : .remote("Overpass reported: \(remark)"))
        }
        return .success(decoded.elements)
    }

    private func request(for query: String, url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(TABAClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = TimeInterval(timeoutSeconds + 30)
        request.httpBody = Data(("data=" + Self.formEncoded(query)).utf8)
        return request
    }

    /// Percent-encodes everything but unreserved characters, so "&", "+" and "=" in the query cannot change the form.
    static func formEncoded(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

/// The Overpass JSON: `{"elements": [...], "remark": "..."}`. `remark` is present when the server reports a problem.
struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
    let remark: String?
}

/// One OSM object. Nodes carry `lat` and `lon`. Ways and relations carry a `center` when the query asks for one.
struct OverpassElement: Decodable {
    struct Centre: Decodable {
        let lat: Double
        let lon: Double
    }

    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: Centre?
    let tags: [String: String]?

    /// The object's point: its own position for a node, or its centre for a way or relation.
    var coordinate: Coordinate? {
        if let lat, let lon {
            return Coordinate(latitude: lat, longitude: lon)
        }
        if let center {
            return Coordinate(latitude: center.lat, longitude: center.lon)
        }
        return nil
    }
}
