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
    /// Overpass's own limit for one query. A larger batch size is capped here.
    static let maximumBatchSize = 25

    public static let defaultEndpoint = "https://overpass-api.de/api/interpreter"
    static let backupEndpoint = "https://overpass.kumi.systems/api/interpreter"

    /// The public Overpass servers, in the order they are tried: the main one, then the backup.
    public static let defaultEndpoints: [URL] = [defaultEndpointURL, url(for: backupEndpoint)]

    private let client: OverpassClient
    private let timeoutSeconds: Int
    private let batchSize: Int

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
        self.client = OverpassClient(fetcher: fetcher, endpoints: endpoints, timeoutSeconds: timeoutSeconds,
                                     retryDelay: retryDelay, sleep: sleep)
        self.timeoutSeconds = timeoutSeconds
        self.batchSize = min(max(batchSize, 1), Self.maximumBatchSize)
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
            switch await client.run(Self.query(for: batch, timeoutSeconds: timeoutSeconds)) {
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
}
