import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FoursquareKit
import GuideKit

/// Finds candidate places in OpenStreetMap through Nominatim's name search. It is the second OpenStreetMap fallback,
/// after Overpass, and it answers in a second or two.
///
/// `sweep` sends one search per phrase, inside a box about the search radius either side of the centre. A phrase
/// is sent once, however many searches use it. Each row becomes the tags of its object: its `extratags`, its `name`,
/// and its `category=type`. A row is kept when it has a name and one of its search's filters selects it. Chains (a
/// `brand` or `brand:wikidata` tag) are dropped. Places are ranked and kept as `OverpassPlacesSource` ranks them.
/// `find` looks one place up by name, with no chain filter, since a suggested place may be a chain on purpose.
///
/// Every request waits for the pacer first. The public policy allows one request per second, so the default pacer does
/// too. Tests inject a clock and a sleeper.
public struct NominatimPlacesSource: Sendable {
    /// One search: a label, the phrases to send to Nominatim, and the tag filters that keep its rows. Each filter is
    /// one Overpass-style selector, such as `["amenity"="cafe"]`.
    public struct Search: Sendable, Hashable {
        public let label: String
        public let phrases: [String]
        public let filters: [String]

        public init(label: String, phrases: [String], filters: [String]) {
            self.label = label
            self.phrases = phrases
            self.filters = filters
        }
    }

    /// Metres in one degree, as the search box is drawn in degrees of latitude and longitude.
    private static let metresPerDegree = 111_320.0
    /// Rows asked for per phrase in a sweep.
    static let sweepRowLimit = 30
    /// Rows asked for in a name lookup.
    static let findRowLimit = 10

    private let fetcher: any HTTPFetching
    private let pacer: RequestPacer

    public init(
        fetcher: any HTTPFetching,
        interval: Duration = .seconds(1),
        now: @escaping RequestPacer.Now = { ContinuousClock.now },
        sleep: @escaping RequestPacer.Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.fetcher = fetcher
        self.pacer = RequestPacer(interval: interval, now: now, sleep: sleep)
    }

    /// Sweeps every search around `centre`, one name search per phrase. Never throws. A phrase that fails is skipped
    /// and the others still run, so the sweep gives the places of the phrases that answered, with the first error set.
    public func sweep(
        searches: [Search],
        around centre: Coordinate,
        radiusMetres: Int = 1500,
        limit: Int = 6,
        checkedAt: LocalDate
    ) async -> OSMSweep.Report {
        let box = Self.viewbox(around: centre, radiusMetres: radiusMetres)
        var rowsByPhrase: [String: [NominatimRow]] = [:]
        var firstError: SourcesError?
        for phrase in Self.uniquePhrases(searches) {
            guard !Task.isCancelled else { break }
            do {
                rowsByPhrase[phrase] = try await rows(for: phrase, viewbox: box, limit: Self.sweepRowLimit)
            } catch {
                firstError = firstError ?? Self.sourcesError(error)
            }
        }
        let results = searches.map { search -> OSMSweep.SearchResult in
            let rows = Self.uniqueRows(search.phrases.flatMap { rowsByPhrase[$0] ?? [] })
            return Self.result(for: search, rows: rows, around: centre, checkedAt: checkedAt)
        }
        return OSMSweep.report(results, limit: limit, checkedAt: checkedAt, error: firstError)
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
        guard !NameTokens.significant(name, cityName: cityName).isEmpty else { return .success(nil) }
        let box = Self.viewbox(around: centre, radiusMetres: radiusMetres)
        do {
            let rows = try await rows(for: name, viewbox: box, limit: Self.findRowLimit)
            return .success(Self.best(for: name, among: rows, near: centre, cityName: cityName,
                                      checkedAt: checkedAt))
        } catch {
            return .failure(Self.sourcesError(error))
        }
    }

    // MARK: Requests

    /// One `/search` request. A reply other than 2xx, or a body that is not a list of rows, is thrown.
    private func rows(for query: String, viewbox: String, limit: Int) async throws -> [NominatimRow] {
        let items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "viewbox", value: viewbox),
            URLQueryItem(name: "bounded", value: "1"),
            URLQueryItem(name: "extratags", value: "1"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "accept-language", value: "en")
        ]
        var components = URLComponents()
        components.scheme = "https"
        components.host = NominatimGeocoder.host
        components.path = "/search"
        components.queryItems = items
        guard let url = components.url else {
            throw SourcesError.invalidRequest("could not build the Nominatim URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(TABAClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await pacer.wait()
        let response = try await fetcher.send(request)
        guard response.isSuccess else {
            throw SourcesError.http(status: response.status)
        }
        do {
            return try JSONDecoder().decode([NominatimRow].self, from: response.body)
        } catch {
            throw SourcesError.malformed("the Nominatim response")
        }
    }

    /// The box a search is drawn in: `radiusMetres` either side of the centre, as "west,north,east,south" in degrees.
    /// Longitude degrees shrink with the cosine of the latitude, so the east and west edges sit closer in.
    static func viewbox(around centre: Coordinate, radiusMetres: Int) -> String {
        let latitudeSpan = Double(radiusMetres) / metresPerDegree
        let longitudeSpan = Double(radiusMetres) / (metresPerDegree * cos(centre.latitude * .pi / 180))
        let values = [
            centre.longitude - longitudeSpan,
            centre.latitude + latitudeSpan,
            centre.longitude + longitudeSpan,
            centre.latitude - latitudeSpan
        ]
        return values.map { String(format: "%.4f", $0) }.joined(separator: ",")
    }

    static func uniquePhrases(_ searches: [Search]) -> [String] {
        var seen = Set<String>()
        return searches.flatMap(\.phrases).filter { seen.insert($0).inserted }
    }

    /// Each object once, however many of the phrases returned it.
    static func uniqueRows(_ rows: [NominatimRow]) -> [NominatimRow] {
        var seen = Set<String>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    private static func sourcesError(_ error: any Error) -> SourcesError {
        (error as? SourcesError) ?? .network(String(describing: error))
    }

    // MARK: Matching and ranking

    /// The search's rows as candidates. `returned` counts the rows that are named, not chains, and selected by a
    /// filter, before the mapper skips any (closed or off) and before the ranking.
    static func result(
        for search: Search,
        rows: [NominatimRow],
        around centre: Coordinate,
        checkedAt: LocalDate
    ) -> OSMSweep.SearchResult {
        var returned = 0
        var candidates: [OSMSweep.Candidate] = []
        for row in rows {
            let extra = textTags(row.extratags)
            let tags = tags(for: row, extra: extra)
            guard OSMPlaceMapper.value("name", in: tags) != nil,
                  !isChain(extra),
                  OSMSweep.selects(search.filters, tags)
            else {
                continue
            }
            returned += 1
            guard let point = row.coordinate,
                  let place = OSMPlaceMapper.makePlace(osmType: row.osmType, osmId: row.osmId, tags: tags,
                                                       coordinate: point, checkedAt: checkedAt)
            else {
                continue
            }
            candidates.append(OSMSweep.Candidate(place: place, score: OSMSweep.score(tags),
                                                 importance: row.importance ?? 0,
                                                 distance: Geo.metres(from: centre, to: point)))
        }
        return OSMSweep.SearchResult(label: search.label, returned: returned, candidates: candidates)
    }

    private struct NamedMatch {
        let place: Place
        let similarity: Double
        let distance: Double
    }

    /// The most similar name among the rows, from `acceptableSimilarity` up. Ties go to the nearest.
    static func best(
        for name: String,
        among rows: [NominatimRow],
        near centre: Coordinate,
        cityName: String?,
        checkedAt: LocalDate
    ) -> Place? {
        let matches = rows.compactMap { row -> NamedMatch? in
            let tags = tags(for: row, extra: textTags(row.extratags))
            guard let point = row.coordinate,
                  let place = OSMPlaceMapper.makePlace(osmType: row.osmType, osmId: row.osmId, tags: tags,
                                                       coordinate: point, checkedAt: checkedAt)
            else {
                return nil
            }
            let similarity = NameTokens.nameSimilarity(name, place.name, cityName: cityName)
            guard similarity >= NameTokens.acceptableSimilarity else { return nil }
            return NamedMatch(place: place, similarity: similarity, distance: Geo.metres(from: centre, to: point))
        }
        return matches.sorted { first, second in
            if first.similarity != second.similarity {
                return first.similarity > second.similarity
            }
            return first.distance < second.distance
        }.first?.place
    }

    /// The row's tags: its extratags, its name, its category as `category=type`, and its address as `addr:` tags
    /// where the extratags have none.
    static func tags(for row: NominatimRow, extra: [String: String]) -> [String: String] {
        var tags = extra
        let address = textTags(row.address)
        let parts: [(key: String, from: [String])] = [
            ("addr:housenumber", ["house_number"]), ("addr:street", ["road", "pedestrian", "footway"]),
            ("addr:city", ["city", "town", "village"]), ("addr:postcode", ["postcode"])
        ]
        for part in parts where tags[part.key] == nil {
            if let value = part.from.lazy.compactMap({ address[$0] }).first {
                tags[part.key] = value
            }
        }
        if let name = row.name {
            tags["name"] = name
        }
        if let category = row.category, let type = row.type {
            tags[category] = type
        }
        return tags
    }

    /// The text values of the extratags. Any other JSON type is left out.
    static func textTags(_ extratags: [String: LossyText]?) -> [String: String] {
        (extratags ?? [:]).compactMapValues(\.text)
    }

    /// A chain has a `brand` or `brand:wikidata` tag. Only the extratags are read, as Nominatim gives them.
    static func isChain(_ extra: [String: String]) -> Bool {
        OSMPlaceMapper.value("brand", in: extra) != nil || OSMPlaceMapper.value("brand:wikidata", in: extra) != nil
    }
}

/// One row of a Nominatim search in `jsonv2` format, with `extratags`. Only the fields the sources read are decoded.
/// Latitude and longitude are strings in that format.
struct NominatimRow: Decodable, Sendable {
    let osmType: String
    let osmId: Int64
    let lat: String
    let lon: String
    let name: String?
    let category: String?
    let type: String?
    let importance: Double?
    let extratags: [String: LossyText]?
    let address: [String: LossyText]?

    enum CodingKeys: String, CodingKey {
        case osmType = "osm_type"
        case osmId = "osm_id"
        case lat
        case lon
        case name
        case category
        case type
        case importance
        case extratags
        case address
    }

    /// "node/123", "way/456" or "relation/789".
    var id: String {
        "\(osmType)/\(osmId)"
    }

    var coordinate: Coordinate? {
        guard let latitude = Double(lat), let longitude = Double(lon) else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
