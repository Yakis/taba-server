import Foundation
import GuideKit
@testable import SourcesKit
import Testing

struct OverpassPlacesSourceTests {
    private let checkedAt = Samples.date("2026-11-14")
    private let centre = Samples.coordinate(55.9500, -3.2000)

    /// Overpass elements as `out tags center` returns them. Nodes carry lat and lon. Ways carry a center. Some are in
    /// the answer to be skipped: an unnamed cafe, a cafe marked off, and a cafe with no hours far away.
    private let elementsJSON = """
    {"version":0.6,"generator":"Overpass API","elements":[
      {"type":"node","id":101,"lat":55.95020,"lon":-3.20020,
       "tags":{"name":"Ember Coffee","amenity":"cafe","opening_hours":"Mo-Su 08:00-17:00",
               "website":"https://ember.example.com","addr:housenumber":"12",
               "addr:street":"High Street","addr:city":"Edinburgh"}},
      {"type":"node","id":102,"lat":55.95100,"lon":-3.20100,
       "tags":{"name":"Harbour Cafe","amenity":"cafe","shop":"bakery","wikidata":"Q100",
               "addr:street":"Rose Street","addr:postcode":"EH2 2NE"}},
      {"type":"node","id":103,"lat":55.95010,"lon":-3.20010,
       "tags":{"amenity":"cafe"}},
      {"type":"node","id":104,"lat":55.95010,"lon":-3.20010,
       "tags":{"name":"Shut Cafe","amenity":"cafe","opening_hours":"off"}},
      {"type":"node","id":105,"lat":55.96000,"lon":-3.20000,
       "tags":{"name":"Quiet Cafe","amenity":"cafe"}},
      {"type":"way","id":201,"center":{"lat":55.94200,"lon":-3.21000},
       "tags":{"name":"Meadow Park","leisure":"park"}},
      {"type":"node","id":301,"lat":55.94800,"lon":-3.19500,
       "tags":{"name":"Greyfriars Memorial","historic":"memorial"}},
      {"type":"node","id":302,"lat":55.94900,"lon":-3.19600,
       "tags":{"name":"Old Castle Hall","historic":"castle"}},
      {"type":"node","id":401,"lat":55.95300,"lon":-3.20300,
       "tags":{"name":"Stockbridge Market","amenity":"marketplace"}},
      {"type":"node","id":402,"lat":55.95400,"lon":-3.20400,
       "tags":{"name":"Deli Corner","shop":"deli"}}
    ]}
    """

    private var cafeSearch: OverpassPlacesSource.Search {
        .init(label: "cafe", filters: [#"["amenity"="cafe"]"#])
    }

    private var sixSearches: [OverpassPlacesSource.Search] {
        [
            cafeSearch,
            .init(label: "shop", filters: [#"["shop"="bakery"]"#]),
            .init(label: "parks", filters: [#"["leisure"="park"]"#]),
            .init(label: "heritage", filters: [#"["historic"~"^(castle|monument|memorial)$"]"#]),
            .init(label: "market", filters: [#"["amenity"="marketplace"]"#]),
            .init(label: "grocery", filters: [#"["shop"~"^(supermarket|greengrocer|deli)$"]"#])
        ]
    }

    /// The Overpass query a request carried, decoded from its form body.
    private func queryText(_ request: URLRequest) -> String {
        let body = request.httpBody.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        let encoded = body.hasPrefix("data=") ? String(body.dropFirst(5)) : body
        return encoded.removingPercentEncoding ?? ""
    }

    private func sweep(
        _ searches: [OverpassPlacesSource.Search],
        limit: Int = 6,
        answer: String? = nil
    ) async -> (OverpassPlacesSource.SweepReport, ScriptedFetcher) {
        let fetcher = ScriptedFetcher([.respond(Samples.response(answer ?? elementsJSON))])
        let source = OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in })
        let report = await source.sweep(searches: searches, around: centre, limit: limit, checkedAt: checkedAt)
        return (report, fetcher)
    }

    private func place(_ id: String, in report: OverpassPlacesSource.SweepReport) -> Place? {
        report.places.first { $0.id == id }
    }

    // MARK: The query

    @Test func theQueryHasOneBranchPerFilterAndTheAroundClause() {
        let query = OverpassPlacesSource.sweepQuery(
            filters: [#"["amenity"="cafe"]"#, #"["shop"~"^(deli|greengrocer)$"]"#],
            around: centre,
            radiusMetres: 1500
        )
        #expect(query.hasPrefix("[out:json][timeout:45];"))
        #expect(query.contains("  nwr[\"amenity\"=\"cafe\"](around:1500,55.950000,-3.200000);"))
        #expect(query.contains("  nwr[\"shop\"~\"^(deli|greengrocer)$\"](around:1500,55.950000,-3.200000);"))
        #expect(query.components(separatedBy: "nwr[").count - 1 == 2)
        #expect(query.hasSuffix("out tags center;"))
    }

    @Test func aSweepSendsOneQueryForAllTheSearches() async {
        let (_, fetcher) = await sweep(sixSearches)
        let requests = await fetcher.requests
        #expect(requests.count == 1)
        let text = requests.first.map(queryText) ?? ""
        #expect(text.contains("nwr[\"amenity\"=\"cafe\"](around:1500,55.950000,-3.200000);"))
        #expect(text.contains("nwr[\"leisure\"=\"park\"](around:1500,55.950000,-3.200000);"))
        #expect(text.components(separatedBy: "nwr[").count - 1 == 6)
    }

    @Test func aSweepTriesTwiceAndWaitsThirtySecondsPastItsQueryTimeout() async throws {
        let fetcher = ScriptedFetcher([.respond(Samples.response("", status: 504)),
                                       .respond(Samples.response("", status: 504))])
        let source = OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in })
        let report = await source.sweep(searches: [cafeSearch], around: centre, checkedAt: checkedAt)
        #expect(report.error == .http(status: 504))
        #expect(report.places.isEmpty)
        let requests = await fetcher.requests
        #expect(requests.count == 2)
        #expect(try #require(requests.first).timeoutInterval == 75)
    }

    @Test func aFilterInTwoSearchesIsAskedForOnce() async {
        let searches = [cafeSearch, .init(label: "cafes again", filters: [#"["amenity"="cafe"]"#])]
        let (_, fetcher) = await sweep(searches)
        let text = await fetcher.requests.first.map(queryText) ?? ""
        #expect(text.components(separatedBy: "nwr[").count - 1 == 1)
    }

    // MARK: Matching and the sweep

    @Test func elementsLandInTheSearchesThatMatchThem() async {
        let (report, _) = await sweep(sixSearches)
        let placeIds = Dictionary(uniqueKeysWithValues: report.sweeps.map { ($0.label, $0.placeIds) })
        #expect(placeIds["parks"] == ["osm:way/201"])
        #expect(placeIds["market"] == ["osm:node/401"])
        #expect(placeIds["grocery"] == ["osm:node/402"])
        #expect(Set(placeIds["heritage"] ?? []) == ["osm:node/301", "osm:node/302"])
        #expect(report.error == nil)
    }

    @Test func unnamedClosedAndUnlocatedElementsAreSkipped() async {
        let (report, _) = await sweep([cafeSearch])
        #expect(place("osm:node/103", in: report) == nil)
        #expect(place("osm:node/104", in: report) == nil)
        #expect(report.places.map(\.id).sorted() == ["osm:node/101", "osm:node/102", "osm:node/105"])
    }

    @Test func theTopRankedElementsWithinTheLimitAreKept() async {
        // Harbour Cafe has Wikidata (score 4), Ember Coffee a website and hours (2), Quiet Cafe neither (0), though
        // it is the only one of the three that is far away. A limit of two keeps the two best.
        let (report, _) = await sweep([cafeSearch], limit: 2)
        let cafe = report.sweeps.first { $0.label == "cafe" }
        #expect(cafe?.placeIds == ["osm:node/102", "osm:node/101"])
        #expect(cafe?.returned == 5)
        #expect(place("osm:node/105", in: report) == nil)
    }

    @Test func aPlaceInTwoSearchesIsListedOnceButEachSearchKeepsIt() async {
        let (report, _) = await sweep(sixSearches)
        #expect(report.places.filter { $0.id == "osm:node/102" }.count == 1)
        #expect(report.sweeps.first { $0.label == "shop" }?.placeIds == ["osm:node/102"])
        #expect(report.sweeps.first { $0.label == "cafe" }?.placeIds.contains("osm:node/102") == true)
        #expect(Set(report.places.map(\.id)).count == report.places.count)
    }

    // MARK: Mapping

    @Test func aCafeMapsToItsKindWithHoursAddressAndWebsite() async throws {
        let (report, _) = await sweep([cafeSearch])
        let ember = try #require(place("osm:node/101", in: report))
        #expect(ember.name == "Ember Coffee")
        #expect(ember.kind == .cafe)
        #expect(ember.indoor)
        #expect(ember.hours.hoursKnown)
        #expect(ember.location.address == "12 High Street, Edinburgh")
        #expect(!ember.location.approximate)
        #expect(ember.location.coordinate == Samples.coordinate(55.95020, -3.20020))
        #expect(ember.priceLevel == nil)
        #expect(ember.booking == PlaceBooking(needed: false, url: nil))
        #expect(ember.images.isEmpty)
        #expect(ember.copy == nil)
        #expect(ember.facts.map(\.text) == ["Website: https://ember.example.com"])
        #expect(ember.facts.map(\.sourceId) == ["osm:node/101"])
        #expect(ember.facts.map(\.checkedAt) == [checkedAt])
    }

    @Test func anAddressWithoutANumberOrACityUsesThePostcode() async throws {
        let (report, _) = await sweep([cafeSearch])
        let harbour = try #require(place("osm:node/102", in: report))
        #expect(harbour.location.address == "Rose Street, EH2 2NE")
        #expect(harbour.kind == .cafe)
        #expect(harbour.facts.isEmpty)
        let quiet = try #require(place("osm:node/105", in: report))
        #expect(quiet.location.address == nil)
        #expect(!quiet.hours.hoursKnown)
    }

    @Test func kindsAndIndoorFollowTheTags() async throws {
        let (report, _) = await sweep(sixSearches)
        let market = try #require(place("osm:node/401", in: report))
        #expect(market.kind == .market)
        #expect(!market.indoor)
        let deli = try #require(place("osm:node/402", in: report))
        #expect(deli.kind == .grocery)
        #expect(deli.indoor)
        let park = try #require(place("osm:way/201", in: report))
        #expect(park.kind == .landmark)
        #expect(!park.indoor)
        #expect(park.location.coordinate == Samples.coordinate(55.94200, -3.21000))
        let memorial = try #require(place("osm:node/301", in: report))
        #expect(memorial.kind == .landmark)
        #expect(!memorial.indoor)
        let castle = try #require(place("osm:node/302", in: report))
        #expect(castle.kind == .landmark)
        #expect(castle.indoor)
    }

    // MARK: Sources

    @Test func aPlaceWithKnownHoursGetsItsOpenStreetMapSource() async {
        let (report, _) = await sweep(sixSearches)
        #expect(report.sources.map(\.id) == ["osm:node/101"])
        let source = report.sources.first
        #expect(source?.url == "https://www.openstreetmap.org/node/101")
        #expect(source?.title == "OpenStreetMap node/101")
        #expect(source?.checkedAt == checkedAt)
    }

    @Test func aSourceIsGivenOnlyForOpenStreetMapIds() throws {
        let source = try #require(OverpassPlacesSource.source(forPlaceId: "osm:way/456", checkedAt: checkedAt))
        #expect(source.id == "osm:way/456")
        #expect(source.url == "https://www.openstreetmap.org/way/456")
        #expect(OverpassPlacesSource.source(forPlaceId: "fsq:abc", checkedAt: checkedAt) == nil)
        #expect(OverpassPlacesSource.source(forPlaceId: "osm:", checkedAt: checkedAt) == nil)
    }

    // MARK: Failure

    @Test func aFailedQueryGivesAnEmptyReportWithTheError() async {
        let fetcher = ScriptedFetcher([.respond(Samples.response("", status: 400))])
        let source = OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in })
        let report = await source.sweep(searches: sixSearches, around: centre, checkedAt: checkedAt)
        #expect(report.places.isEmpty)
        #expect(report.sources.isEmpty)
        #expect(report.error == .http(status: 400))
        #expect(report.sweeps.map(\.label) == sixSearches.map(\.label))
        #expect(report.sweeps.allSatisfy { $0.returned == 0 && $0.placeIds.isEmpty })
    }

    @Test func aSweepWithNoFiltersSendsNothing() async {
        let (report, fetcher) = await sweep([.init(label: "none", filters: [])])
        #expect(await fetcher.requests.isEmpty)
        #expect(report.places.isEmpty)
        #expect(report.sweeps == [.init(label: "none", returned: 0, placeIds: [])])
    }

    // MARK: Tag selectors

    @Test func tagSelectorsReadTheExactAndTheAlternationForms() throws {
        let exact = try #require(TagSelector(#"["amenity"="cafe"]"#))
        #expect(exact.matches(["amenity": "cafe"]))
        #expect(!exact.matches(["amenity": "cafes"]))
        #expect(!exact.matches(["shop": "cafe"]))

        let alternation = try #require(TagSelector(#"["shop"~"^(supermarket|greengrocer|deli)$"]"#))
        #expect(alternation.matches(["shop": "deli"]))
        #expect(alternation.matches(["shop": "greengrocer"]))
        #expect(!alternation.matches(["shop": "delicatessen"]))
        #expect(!alternation.matches([:]))
    }

    @Test func aSelectorOfAnotherFormIsNotRead() {
        #expect(TagSelector(#"["name"~"oak",i]"#) == nil)
        #expect(TagSelector(#"["amenity"]"#) == nil)
        #expect(TagSelector("amenity=cafe") == nil)
    }
}
