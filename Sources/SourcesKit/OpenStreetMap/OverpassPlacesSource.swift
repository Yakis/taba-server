import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoursquareKit
import GuideKit

/// Finds candidate places in OpenStreetMap through Overpass. A build asks it only when Nominatim gives
/// nothing.
///
/// `sweep` runs every search in one Overpass query. Each filter is one union branch around the centre, and an element
/// goes to every search that has a filter it matches. Elements without a name or a coordinate, and those whose
/// `opening_hours` says closed or off, are skipped. Each search keeps its best `limit` elements: those with a Wikidata
/// or Wikipedia tag first, then those with a website or opening hours, then the nearest. A place is listed once in
/// `report.places`, though several searches may return it. `find` looks one place up by name. Both send at most two
/// attempts with a 45 second query timeout, so a slow server cannot hold a stage for long.
public struct OverpassPlacesSource: Sendable {
    /// The prefix of every place id from OpenStreetMap, as in "osm:node/123".
    public static let idPrefix = "osm:"
    static let timeoutSeconds = 45
    /// The first try and one retry.
    static let attempts = 2

    /// One search: a label, and the tag filters that find its places. Each filter is one Overpass selector, such as
    /// `["amenity"="cafe"]` or `["shop"~"^(supermarket|greengrocer|deli)$"]`.
    public struct Search: Sendable, Hashable {
        public let label: String
        public let filters: [String]

        public init(label: String, filters: [String]) {
            self.label = label
            self.filters = filters
        }
    }

    /// What one search did. `returned` counts the elements the query matched to the search, before the skips.
    public typealias SweepOutcome = OSMSweep.Outcome

    public typealias SweepReport = OSMSweep.Report

    private let client: OverpassClient

    /// - Parameters:
    ///   - endpoints: Tried in rotation. Empty falls back to `OverpassHoursSource.defaultEndpoints`.
    ///   - retryDelay: The wait before the one retry. Tests pass zero.
    ///   - sleep: Injected so tests do not wait.
    public init(
        fetcher: any HTTPFetching,
        endpoints: [URL] = [],
        retryDelay: Duration = .seconds(10),
        sleep: @escaping OverpassHoursSource.Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.client = OverpassClient(fetcher: fetcher, endpoints: endpoints, timeoutSeconds: Self.timeoutSeconds,
                                     retryDelay: retryDelay, attempts: Self.attempts, sleep: sleep)
    }

    /// Sweeps every search around `centre` in one query. Never throws. A failed query gives no places, one outcome per
    /// search with nothing in it, and the error.
    public func sweep(
        searches: [Search],
        around centre: Coordinate,
        radiusMetres: Int = 1500,
        limit: Int = 6,
        checkedAt: LocalDate
    ) async -> SweepReport {
        let filters = Self.uniqueFilters(searches)
        guard !filters.isEmpty else {
            return OSMSweep.emptyReport(labels: searches.map(\.label), error: nil)
        }
        let query = Self.sweepQuery(filters: filters, around: centre, radiusMetres: radiusMetres)
        switch await client.run(query) {
        case .failure(let error):
            return OSMSweep.emptyReport(labels: searches.map(\.label), error: error)
        case .success(let elements):
            return Self.report(searches: searches, elements: elements, around: centre, limit: limit,
                               checkedAt: checkedAt)
        }
    }

    /// The place with the name most like `name` within `radiusMetres` of `centre`, or nil when none is similar enough.
    /// It sends no request when the name has no significant word. Never throws.
    public func find(
        named name: String,
        near centre: Coordinate,
        radiusMetres: Int = 10_000,
        cityName: String?,
        checkedAt: LocalDate
    ) async -> Result<Place?, SourcesError> {
        let tokens = Array(NameTokens.significant(name, cityName: cityName).prefix(3))
        guard !tokens.isEmpty else { return .success(nil) }
        let query = Self.findQuery(tokens: tokens, around: centre, radiusMetres: radiusMetres)
        switch await client.run(query) {
        case .failure(let error):
            return .failure(error)
        case .success(let elements):
            return .success(Self.best(for: name, among: elements, near: centre, cityName: cityName,
                                      checkedAt: checkedAt))
        }
    }

    /// The source page of an OpenStreetMap place: "osm:node/123" maps to its OpenStreetMap page. Nil for any other id.
    public static func source(forPlaceId id: String, checkedAt: LocalDate) -> Source? {
        guard id.hasPrefix(idPrefix) else { return nil }
        let osmId = String(id.dropFirst(idPrefix.count))
        guard !osmId.isEmpty else { return nil }
        return Source(
            id: id,
            url: "https://www.openstreetmap.org/\(osmId)",
            title: "OpenStreetMap \(osmId)",
            checkedAt: checkedAt
        )
    }

    // MARK: Queries

    static func uniqueFilters(_ searches: [Search]) -> [String] {
        var seen = Set<String>()
        return searches.flatMap(\.filters).filter { seen.insert($0).inserted }
    }

    static func sweepQuery(filters: [String], around centre: Coordinate, radiusMetres: Int) -> String {
        let latitude = String(format: "%.6f", centre.latitude)
        let longitude = String(format: "%.6f", centre.longitude)
        var lines = ["[out:json][timeout:\(timeoutSeconds)];", "("]
        for filter in filters {
            lines.append("  nwr\(filter)(around:\(radiusMetres),\(latitude),\(longitude));")
        }
        lines.append(");")
        lines.append("out tags center;")
        return lines.joined(separator: "\n")
    }

    /// One statement whose name must hold every token, so a common word such as "market" cannot crowd out the place.
    static func findQuery(tokens: [String], around centre: Coordinate, radiusMetres: Int) -> String {
        let latitude = String(format: "%.6f", centre.latitude)
        let longitude = String(format: "%.6f", centre.longitude)
        let names = tokens.map { "[\"name\"~\"\(namePattern($0))\",i]" }.joined()
        return [
            "[out:json][timeout:\(timeoutSeconds)];",
            "nwr\(names)(around:\(radiusMetres),\(latitude),\(longitude));",
            "out tags center 30;"
        ].joined(separator: "\n")
    }

    /// The token as a pattern. A token ending in "s" also matches the possessive, so "makars" finds "Makar's".
    static func namePattern(_ token: String) -> String {
        guard token.count > 2, token.hasSuffix("s") else { return escapedRegex(token) }
        return escapedRegex(String(token.dropLast())) + "['’]?s"
    }

    /// Escapes the characters a regular expression would read as syntax, and the quote and backslash of the query.
    static func escapedRegex(_ text: String) -> String {
        let special = Set("\\.^$|()[]{}*+?\"")
        var result = ""
        for character in text {
            if special.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    // MARK: Matching

    private struct NamedMatch {
        let place: Place
        let similarity: Double
        let distance: Double
    }

    static func report(
        searches: [Search],
        elements: [OverpassElement],
        around centre: Coordinate,
        limit: Int,
        checkedAt: LocalDate
    ) -> SweepReport {
        let results = searches.map { search -> OSMSweep.SearchResult in
            let matched = elements.filter { matches(search, $0) }
            let candidates = matched.compactMap { element -> OSMSweep.Candidate? in
                guard let place = OSMPlaceMapper.makePlace(from: element, checkedAt: checkedAt),
                      let point = element.coordinate
                else {
                    return nil
                }
                return OSMSweep.Candidate(place: place, score: OSMSweep.score(element.tags ?? [:]), importance: 0,
                                          distance: Geo.metres(from: centre, to: point))
            }
            return OSMSweep.SearchResult(label: search.label, returned: matched.count, candidates: candidates)
        }
        return OSMSweep.report(results, limit: limit, checkedAt: checkedAt, error: nil)
    }

    /// The most similar name among the elements, from `similarity` up to the threshold. Ties go to the nearest.
    static func best(
        for name: String,
        among elements: [OverpassElement],
        near centre: Coordinate,
        cityName: String?,
        checkedAt: LocalDate
    ) -> Place? {
        let namedMatches = elements.compactMap { element -> NamedMatch? in
            guard let place = OSMPlaceMapper.makePlace(from: element, checkedAt: checkedAt),
                  let point = element.coordinate
            else {
                return nil
            }
            let similarity = NameTokens.nameSimilarity(name, place.name, cityName: cityName)
            guard similarity >= NameTokens.acceptableSimilarity else { return nil }
            return NamedMatch(place: place, similarity: similarity, distance: Geo.metres(from: centre, to: point))
        }
        return namedMatches.sorted { first, second in
            if first.similarity != second.similarity {
                return first.similarity > second.similarity
            }
            return first.distance < second.distance
        }.first?.place
    }

    /// True when the element has a tag that one of the search's filters selects.
    static func matches(_ search: Search, _ element: OverpassElement) -> Bool {
        OSMSweep.selects(search.filters, element.tags ?? [:])
    }
}

/// One tag selector from a filter: `["key"="value"]`, or `["key"~"^(a|b|c)$"]` for a list of values. These are the only
/// two forms the searches use, so nothing else is read. Anything else is nil.
struct TagSelector: Equatable, Sendable {
    let key: String
    let values: [String]

    init?(_ filter: String) {
        guard filter.hasPrefix("["), filter.hasSuffix("]") else { return nil }
        let parts = filter.dropFirst().dropLast().components(separatedBy: "\"")
        guard parts.count == 5, parts[0].isEmpty, parts[4].isEmpty, !parts[1].isEmpty else { return nil }
        key = parts[1]
        switch parts[2] {
        case "=":
            values = [parts[3]]
        case "~":
            let pattern = parts[3]
            guard pattern.hasPrefix("^("), pattern.hasSuffix(")$") else { return nil }
            let list = pattern.dropFirst(2).dropLast(2).split(separator: "|").map(String.init)
            guard !list.isEmpty else { return nil }
            values = list
        default:
            return nil
        }
    }

    func matches(_ tags: [String: String]) -> Bool {
        guard let value = tags[key] else { return false }
        return values.contains(value)
    }
}
