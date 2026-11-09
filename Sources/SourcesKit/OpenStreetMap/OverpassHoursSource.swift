import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoursquareKit
import GuideKit

/// A place to look up in OpenStreetMap.
public struct HoursLookupTarget: Sendable, Equatable {
    public let placeId: String
    public let name: String
    public let coordinate: Coordinate

    public init(placeId: String, name: String, coordinate: Coordinate) {
        self.placeId = placeId
        self.name = name
        self.coordinate = coordinate
    }
}

/// An OSM object that matched a place, with its opening hours read.
public struct OSMHours: Sendable, Equatable {
    /// The object as "node/123", "way/456" or "relation/789".
    public let osmId: String
    public let rawOpeningHours: String
    public let reading: OpeningHoursReading
    /// The OSM object's page, as a guide source.
    public let source: Source
}

public enum OSMHoursOutcome: Sendable, Equatable {
    /// An object with an `opening_hours` tag matched the place by name, within 80 m.
    case found(OSMHours)
    /// No such object was found near the place.
    case notFound
    /// Overpass did not answer for this place's batch. Its hours are unknown.
    case unavailable
}

public struct OSMLookupResult: Sendable, Equatable {
    public let placeId: String
    public let outcome: OSMHoursOutcome
}

/// The result of a whole lookup: one result per target, in target order. `error` is set when any batch failed. The
/// places in a failed batch are `.unavailable`, and the rest of the lookup still stands.
public struct OverpassLookup: Sendable, Equatable {
    public let results: [OSMLookupResult]
    public let error: SourcesError?
}

/// Finds each place's OpenStreetMap object by name, within 80 m, and reads its `opening_hours` tag.
///
/// Each batch of up to 25 targets is one Overpass query. Each target is one `nwr["opening_hours"](around:80,...)`
/// union branch, so only objects with hours come back. Those objects are matched to targets here, by name and by
/// distance. Batches run one after another. A batch that times out, loses its connection, or gets a 429, 502, 503 or
/// 504, is retried up to three times, with waits of `retryDelay`, then twice that, then four times that. Each attempt
/// uses the next endpoint in the list, so the endpoints take turns. Any other failure is not retried. No failure
/// throws: it is reported in `OverpassLookup.error`, and the affected places are `.unavailable`.
public struct OverpassHoursSource: Sendable {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    public static let radiusMetres = 80
    /// Attempts per batch: the first try and three retries.
    static let attempts = 4
    /// Overpass's own limit for one query. A larger batch size is capped here.
    static let maximumBatchSize = 25

    public static let defaultEndpoint = "https://overpass-api.de/api/interpreter"
    static let backupEndpoint = "https://overpass.kumi.systems/api/interpreter"

    /// The public Overpass servers, in the order they are tried: the main one, then the backup.
    public static let defaultEndpoints: [URL] = [defaultEndpointURL, url(for: backupEndpoint)]

    private let fetcher: any HTTPFetching
    private let endpoints: [URL]
    private let timeoutSeconds: Int
    private let batchSize: Int
    private let retryDelay: Duration
    private let sleep: Sleep

    /// - Parameters:
    ///   - endpoints: Tried in rotation, one per attempt, so the first attempt uses the first endpoint, the second
    ///     attempt the second, and so on, wrapping round. Empty falls back to `defaultEndpoints`.
    ///   - timeoutSeconds: The `[timeout:]` in each query. The request waits 30 seconds longer than this.
    ///   - batchSize: Targets per query, between 1 and 25.
    ///   - retryDelay: The wait before the first retry. Each later retry waits twice as long as the one before.
    ///   - sleep: Injected so tests do not wait.
    public init(
        fetcher: any HTTPFetching,
        endpoints: [URL] = OverpassHoursSource.defaultEndpoints,
        timeoutSeconds: Int = 90,
        batchSize: Int = 25,
        retryDelay: Duration = .seconds(10),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.fetcher = fetcher
        self.endpoints = endpoints.isEmpty ? Self.defaultEndpoints : endpoints
        self.timeoutSeconds = timeoutSeconds
        self.batchSize = min(max(batchSize, 1), Self.maximumBatchSize)
        self.retryDelay = retryDelay
        self.sleep = sleep
    }

    public static var defaultEndpointURL: URL {
        url(for: defaultEndpoint)
    }

    private static func url(for string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("the Overpass endpoint is a valid URL")
        }
        return url
    }

    /// Looks up every target. Never throws. With no targets it sends nothing.
    public func hours(
        for targets: [HoursLookupTarget],
        cityName: String?,
        checkedAt: LocalDate
    ) async -> OverpassLookup {
        var results: [OSMLookupResult] = []
        var firstError: SourcesError?
        for batch in batches(of: targets) {
            switch await fetch(batch) {
            case .success(let elements):
                results += batch.map { target in
                    OSMLookupResult(
                        placeId: target.placeId,
                        outcome: Self.outcome(for: target, in: elements, cityName: cityName, checkedAt: checkedAt)
                    )
                }
            case .failure(let error):
                firstError = firstError ?? error
                results += batch.map { OSMLookupResult(placeId: $0.placeId, outcome: .unavailable) }
            }
        }
        return OverpassLookup(results: results, error: firstError)
    }

    private func batches(of targets: [HoursLookupTarget]) -> [[HoursLookupTarget]] {
        stride(from: 0, to: targets.count, by: batchSize).map { start in
            Array(targets[start..<min(start + batchSize, targets.count)])
        }
    }

    /// One batch, with its permitted retries for a retryable failure. The wait before retry N doubles each time.
    private func fetch(_ batch: [HoursLookupTarget]) async -> Result<[OverpassElement], SourcesError> {
        let query = Self.query(for: batch, timeoutSeconds: timeoutSeconds)
        var lastError = SourcesError.refused("no attempt was made")
        for attempt in 0..<Self.attempts {
            let url = endpoints[attempt % endpoints.count]
            switch await send(query: query, to: url) {
            case .success(let elements):
                return .success(elements)
            case .failure(let error):
                lastError = error
                guard attempt + 1 < Self.attempts, Self.isRetryable(error) else {
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

    /// The Overpass QL for a batch: one union branch per target, then the tags and centre of each match.
    static func query(for targets: [HoursLookupTarget], timeoutSeconds: Int) -> String {
        var lines = ["[out:json][timeout:\(timeoutSeconds)];", "("]
        for target in targets {
            let latitude = String(format: "%.6f", target.coordinate.latitude)
            let longitude = String(format: "%.6f", target.coordinate.longitude)
            lines.append("  nwr[\"opening_hours\"](around:\(radiusMetres),\(latitude),\(longitude));")
        }
        lines.append(");")
        lines.append("out tags center;")
        return lines.joined(separator: "\n")
    }

    private struct Candidate {
        let element: OverpassElement
        let similarity: Double
        let distance: Double
    }

    /// The best object for one target: the closest name match within 80 m that has an opening_hours tag.
    static func outcome(
        for target: HoursLookupTarget,
        in elements: [OverpassElement],
        cityName: String?,
        checkedAt: LocalDate
    ) -> OSMHoursOutcome {
        let candidates = elements.compactMap { element -> Candidate? in
            guard let name = element.tags?["name"],
                  let raw = element.tags?["opening_hours"], !raw.isEmpty,
                  let point = element.coordinate
            else {
                return nil
            }
            let distance = Geo.metres(from: target.coordinate, to: point)
            guard distance <= Double(radiusMetres) else { return nil }
            let similarity = NameTokens.nameSimilarity(target.name, name, cityName: cityName)
            guard similarity >= NameTokens.acceptableSimilarity else { return nil }
            return Candidate(element: element, similarity: similarity, distance: distance)
        }
        let ranked = candidates.sorted { first, second in
            if first.similarity != second.similarity {
                return first.similarity > second.similarity
            }
            return first.distance < second.distance
        }
        guard let best = ranked.first, let raw = best.element.tags?["opening_hours"] else {
            return .notFound
        }
        let osmId = "\(best.element.type)/\(best.element.id)"
        let source = Source(
            id: "osm:\(osmId)",
            url: "https://www.openstreetmap.org/\(osmId)",
            title: "OpenStreetMap \(osmId)",
            checkedAt: checkedAt
        )
        let hours = OSMHours(
            osmId: osmId,
            rawOpeningHours: raw,
            reading: OpeningHoursParser.parse(raw),
            source: source
        )
        return .found(hours)
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
