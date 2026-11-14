import Foundation
import GuideKit
@testable import SourcesKit
import Testing

/// Rows for the "cafe" phrase, written by hand in Nominatim's jsonv2 shape with extratags. Row 103 has no name, 104 is
/// marked off, 105 has no extratags, and 106 is a chain.
private let cafeRows = """
[
 {"osm_type":"node","osm_id":101,"lat":"55.95020","lon":"-3.20020","category":"amenity","type":"cafe",
  "name":"Ember Coffee","importance":0.00002,
  "extratags":{"opening_hours":"Mo-Su 08:00-17:00","website":"https://ember.example.com"}},
 {"osm_type":"node","osm_id":102,"lat":"55.95100","lon":"-3.20100","category":"amenity","type":"cafe",
  "name":"Harbour Cafe","importance":0.00001,"extratags":{"wikidata":"Q100"}},
 {"osm_type":"node","osm_id":103,"lat":"55.95010","lon":"-3.20010","category":"amenity","type":"cafe",
  "importance":0.5},
 {"osm_type":"node","osm_id":104,"lat":"55.95010","lon":"-3.20010","category":"amenity","type":"cafe",
  "name":"Shut Cafe","importance":0.1,"extratags":{"opening_hours":"off"}},
 {"osm_type":"node","osm_id":105,"lat":"55.96000","lon":"-3.20000","category":"amenity","type":"cafe",
  "name":"Quiet Cafe","importance":0.2},
 {"osm_type":"node","osm_id":106,"lat":"55.95200","lon":"-3.20200","category":"amenity","type":"cafe",
  "name":"Corner Chain Cafe","importance":0.9,"extratags":{"brand":"Corner Chain","brand:wikidata":"Q1"}}
]
"""

/// Rows for the "park" phrase. A parking garage is named "park" in the search, so the parks filter must drop it.
private let parkRows = """
[
 {"osm_type":"way","osm_id":201,"lat":"55.94200","lon":"-3.21000","category":"leisure","type":"park",
  "name":"Meadow Park","importance":0.3},
 {"osm_type":"node","osm_id":202,"lat":"55.95500","lon":"-3.19900","category":"amenity","type":"parking",
  "name":"Q-Park","importance":0.4}
]
"""

/// Rows for a name lookup of "Makars Mash Bar": a near miss, a close name, a closer name, and one far away.
private let makarsRows = """
[
 {"osm_type":"node","osm_id":501,"lat":"55.9510","lon":"-3.2010","category":"amenity","type":"pub",
  "name":"Oink","importance":0.1},
 {"osm_type":"node","osm_id":502,"lat":"55.9500","lon":"-3.2000","category":"amenity","type":"pub",
  "name":"Makars","importance":0.1},
 {"osm_type":"node","osm_id":503,"lat":"55.9400","lon":"-3.2300","category":"amenity","type":"pub",
  "name":"Makars Mash House","importance":0.2}
]
"""

struct NominatimPlacesSourceTests {
    private let checkedAt = Samples.date("2026-11-14")
    private let centre = Samples.coordinate(55.9500, -3.2000)

    private let cafeSearch = NominatimPlacesSource.Search(
        label: "cafe", phrases: ["cafe"], filters: [#"["amenity"="cafe"]"#])
    private let parksSearch = NominatimPlacesSource.Search(
        label: "parks", phrases: ["park"], filters: [#"["leisure"="park"]"#, #"["leisure"="garden"]"#])

    /// A source whose answers come from `rows`, keyed by the query, with rows of "[]" for any other query. Queries in
    /// `failing` get a 503. Nothing waits.
    private func makeSource(
        rows: [String: String],
        failing: Set<String> = []
    ) -> (NominatimPlacesSource, RecordingFetcher) {
        let fetcher = RecordingFetcher { request in
            let query = Samples.query(request)["q"] ?? ""
            if failing.contains(query) {
                return Samples.response("", status: 503)
            }
            return Samples.response(rows[query] ?? "[]")
        }
        let source = NominatimPlacesSource(fetcher: fetcher, interval: .zero, sleep: { _ in })
        return (source, fetcher)
    }

    private func sweep(
        _ searches: [NominatimPlacesSource.Search],
        rows: [String: String] = ["cafe": cafeRows, "park": parkRows],
        failing: Set<String> = [],
        limit: Int = 6
    ) async -> (OSMSweep.Report, RecordingFetcher) {
        let (source, fetcher) = makeSource(rows: rows, failing: failing)
        let report = await source.sweep(searches: searches, around: centre, limit: limit, checkedAt: checkedAt)
        return (report, fetcher)
    }

    private func place(_ id: String, in report: OSMSweep.Report) -> Place? {
        report.places.first { $0.id == id }
    }

    // MARK: Requests

    @Test func aPhraseIsSentAsANameSearchInsideTheBox() async throws {
        let (_, fetcher) = await sweep([cafeSearch])
        let request = try #require(await fetcher.requests.first)
        #expect(request.url?.host == "nominatim.openstreetmap.org")
        #expect(request.url?.path == "/search")
        let query = Samples.query(request)
        #expect(query["q"] == "cafe")
        #expect(query["format"] == "jsonv2")
        #expect(query["limit"] == "30")
        #expect(query["viewbox"] == "-3.2241,55.9635,-3.1759,55.9365")
        #expect(query["bounded"] == "1")
        #expect(query["extratags"] == "1")
        #expect(query["accept-language"] == "en")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "TABA/0.1 (personal travel guide)")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func theBoxIsTheSearchRadiusEitherSideOfTheCentre() {
        #expect(NominatimPlacesSource.viewbox(around: centre, radiusMetres: 10_000)
            == "-3.3604,56.0398,-3.0396,55.8602")
    }

    @Test func aPhraseIsSentOnceEvenWhenTwoSearchesUseIt() async {
        let sameFilter = NominatimPlacesSource.Search(label: "cafes again", phrases: ["cafe"],
                                                      filters: [#"["amenity"="cafe"]"#])
        let (report, fetcher) = await sweep([cafeSearch, sameFilter])
        #expect(await fetcher.requests.count == 1)
        let ids = report.sweeps.map(\.placeIds)
        #expect(ids[0] == ids[1])
        #expect(Set(report.places.map(\.id)).count == report.places.count)
    }

    @Test func requestsAreSpacedOneSecondApart() async {
        let clock = FakeClock()
        let fetcher = RecordingFetcher { _ in Samples.response("[]") }
        let source = NominatimPlacesSource(fetcher: fetcher, interval: .seconds(1),
                                           now: { clock.now }, sleep: { clock.sleep($0) })
        let searches = [NominatimPlacesSource.Search(label: "all", phrases: ["cafe", "park", "deli"], filters: [])]
        _ = await source.sweep(searches: searches, around: centre, checkedAt: checkedAt)
        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
    }

    // MARK: Filters and chains

    @Test func rowsOutsideTheFiltersAreDropped() async {
        let (report, _) = await sweep([parksSearch])
        #expect(report.sweeps.first?.returned == 1)
        #expect(report.sweeps.first?.placeIds == ["osm:way/201"])
        #expect(place("osm:node/202", in: report) == nil)
        #expect(report.places.map(\.id) == ["osm:way/201"])
    }

    @Test func unnamedRowsAndChainsAreDroppedAndNotCounted() async {
        let (report, _) = await sweep([cafeSearch])
        #expect(report.sweeps.first?.returned == 4)
        #expect(place("osm:node/103", in: report) == nil)
        #expect(place("osm:node/106", in: report) == nil)
        #expect(report.places.map(\.id).sorted() == ["osm:node/101", "osm:node/102", "osm:node/105"])
    }

    @Test func aRowMarkedClosedOrOffIsSkippedAfterBeingCounted() async {
        let (report, _) = await sweep([cafeSearch])
        #expect(place("osm:node/104", in: report) == nil)
        #expect(report.sweeps.first?.returned == 4)
    }

    // MARK: Ranking

    @Test func theTopRankedRowsWithinTheLimitAreKept() async {
        // Harbour Cafe has Wikidata (score 4), Ember Coffee a website and hours (2), Quiet Cafe neither (0).
        let (report, _) = await sweep([cafeSearch], limit: 2)
        #expect(report.sweeps.first?.placeIds == ["osm:node/102", "osm:node/101"])
        #expect(place("osm:node/105", in: report) == nil)
    }

    @Test func importanceBreaksTiesAndThenDistanceDoes() async {
        let rows = """
        [
         {"osm_type":"node","osm_id":811,"lat":"55.95010","lon":"-3.20010","category":"amenity","type":"cafe",
          "name":"Plain Cafe","importance":0.1},
         {"osm_type":"node","osm_id":812,"lat":"55.96000","lon":"-3.20000","category":"amenity","type":"cafe",
          "name":"Famous Cafe","importance":0.4},
         {"osm_type":"node","osm_id":813,"lat":"55.95200","lon":"-3.20200","category":"amenity","type":"cafe",
          "name":"Twin Cafe A","importance":0.3},
         {"osm_type":"node","osm_id":814,"lat":"55.95030","lon":"-3.20030","category":"amenity","type":"cafe",
          "name":"Twin Cafe B","importance":0.3}
        ]
        """
        let (byImportance, _) = await sweep([cafeSearch], rows: ["cafe": rows], limit: 1)
        #expect(byImportance.sweeps.first?.placeIds == ["osm:node/812"])
        let twins = """
        [
         {"osm_type":"node","osm_id":813,"lat":"55.95200","lon":"-3.20200","category":"amenity","type":"cafe",
          "name":"Twin Cafe A","importance":0.3},
         {"osm_type":"node","osm_id":814,"lat":"55.95030","lon":"-3.20030","category":"amenity","type":"cafe",
          "name":"Twin Cafe B","importance":0.3}
        ]
        """
        let (nearest, _) = await sweep([cafeSearch], rows: ["cafe": twins], limit: 1)
        #expect(nearest.sweeps.first?.placeIds == ["osm:node/814"])
    }

    // MARK: De-duplication and mapping

    @Test func aPlaceKeptByTwoSearchesIsListedOnceAndEachSearchNamesIt() async {
        let sameFilter = NominatimPlacesSource.Search(label: "cafes again", phrases: ["cafe"],
                                                      filters: [#"["amenity"="cafe"]"#])
        let (report, _) = await sweep([cafeSearch, sameFilter])
        #expect(report.places.filter { $0.id == "osm:node/101" }.count == 1)
        #expect(report.sweeps.allSatisfy { $0.placeIds.contains("osm:node/101") })
    }

    @Test func aRowMapsToItsKindHoursWebsiteAndSource() async throws {
        let (report, _) = await sweep([cafeSearch])
        let ember = try #require(place("osm:node/101", in: report))
        #expect(ember.name == "Ember Coffee")
        #expect(ember.kind == .cafe)
        #expect(ember.indoor)
        #expect(ember.hours.hoursKnown)
        #expect(ember.location.coordinate == Samples.coordinate(55.95020, -3.20020))
        #expect(!ember.location.approximate)
        #expect(ember.location.address == nil)
        #expect(ember.facts.map(\.text) == ["Website: https://ember.example.com"])
        #expect(ember.facts.map(\.sourceId) == ["osm:node/101"])
        #expect(report.sources.map(\.id) == ["osm:node/101"])
        let source = report.sources.first
        #expect(source?.url == "https://www.openstreetmap.org/node/101")
        #expect(source?.checkedAt == checkedAt)
    }

    @Test func aParkMapsToALandmarkOutdoors() async throws {
        let (report, _) = await sweep([parksSearch])
        let park = try #require(place("osm:way/201", in: report))
        #expect(park.kind == .landmark)
        #expect(!park.indoor)
        #expect(park.location.coordinate == Samples.coordinate(55.94200, -3.21000))
        #expect(!park.hours.hoursKnown)
        #expect(park.facts.isEmpty)
    }

    // MARK: Failure

    @Test func aFailedPhraseIsSkippedWhileTheOthersCount() async {
        let restaurant = NominatimPlacesSource.Search(label: "restaurant", phrases: ["restaurant"],
                                                      filters: [#"["amenity"="restaurant"]"#])
        let (report, _) = await sweep([cafeSearch, restaurant], failing: ["restaurant"])
        #expect(report.error == .http(status: 503))
        #expect(report.places.contains { $0.id == "osm:node/101" })
        #expect(report.sweeps.first { $0.label == "restaurant" }?.returned == 0)
        #expect(report.sweeps.first { $0.label == "restaurant" }?.placeIds == [])
    }

    @Test func ifEveryPhraseFailsThereAreNoPlaces() async {
        let (report, _) = await sweep([cafeSearch], failing: ["cafe"])
        #expect(report.places.isEmpty)
        #expect(report.sources.isEmpty)
        #expect(report.error == .http(status: 503))
        #expect(report.sweeps == [.init(label: "cafe", returned: 0, placeIds: [])])
    }

    @Test func aSweepWithNoPhrasesSendsNothing() async {
        let (report, fetcher) = await sweep([.init(label: "none", phrases: [], filters: [])])
        #expect(await fetcher.requests.isEmpty)
        #expect(report.places.isEmpty)
        #expect(report.error == nil)
    }

    // MARK: Name lookup

    @Test func findPicksTheMostSimilarName() async throws {
        let (source, fetcher) = makeSource(rows: ["Makars Mash Bar": makarsRows])
        let found = try #require(try await source.find(named: "Makars Mash Bar", near: centre, cityName: "Edinburgh",
                                                       checkedAt: checkedAt).get())
        #expect(found.id == "osm:node/503")
        #expect(found.kind == .pub)
        let request = try #require(await fetcher.requests.first)
        let query = Samples.query(request)
        #expect(query["q"] == "Makars Mash Bar")
        #expect(query["limit"] == "10")
        #expect(query["viewbox"] == "-3.3604,56.0398,-3.0396,55.8602")
        #expect(query["bounded"] == "1")
        #expect(query["extratags"] == "1")
    }

    @Test func findTiesGoToTheNearest() async throws {
        let rows = """
        [
         {"osm_type":"node","osm_id":601,"lat":"55.9600","lon":"-3.2000","category":"amenity","type":"pub",
          "name":"Makars Mash Bar"},
         {"osm_type":"node","osm_id":602,"lat":"55.9505","lon":"-3.2005","category":"amenity","type":"pub",
          "name":"Makars Mash Bar"}
        ]
        """
        let (source, _) = makeSource(rows: ["Makars Mash Bar": rows])
        let found = try #require(try await source.find(named: "Makars Mash Bar", near: centre, cityName: nil,
                                                       checkedAt: checkedAt).get())
        #expect(found.id == "osm:node/602")
    }

    @Test func findReturnsNothingBelowTheSimilarityThreshold() async throws {
        let rows = """
        [{"osm_type":"node","osm_id":701,"lat":"55.9500","lon":"-3.2000","category":"amenity","type":"pub",
          "name":"Harbour Fish Market"}]
        """
        let (source, _) = makeSource(rows: ["Harbour Lights Club": rows])
        let result = await source.find(named: "Harbour Lights Club", near: centre, cityName: "Edinburgh",
                                       checkedAt: checkedAt)
        #expect(try result.get() == nil)
    }

    @Test func findDoesNotDropChains() async throws {
        let rows = """
        [{"osm_type":"node","osm_id":801,"lat":"55.9500","lon":"-3.2000","category":"amenity","type":"fast_food",
          "name":"Nando's","importance":0.3,"extratags":{"brand":"Nando's"}}]
        """
        let (source, _) = makeSource(rows: ["Nando's": rows])
        let found = try #require(try await source.find(named: "Nando's", near: centre, cityName: "Edinburgh",
                                                       checkedAt: checkedAt).get())
        #expect(found.id == "osm:node/801")
    }

    @Test func findSendsNoRequestWithoutASignificantWord() async throws {
        let (source, fetcher) = makeSource(rows: [:])
        let result = await source.find(named: "  ", near: centre, cityName: "Edinburgh", checkedAt: checkedAt)
        #expect(try result.get() == nil)
        #expect(await fetcher.requests.isEmpty)
    }

    @Test func aFailedNameLookupIsAFailure() async {
        let (source, _) = makeSource(rows: [:], failing: ["Makars Mash Bar"])
        let result = await source.find(named: "Makars Mash Bar", near: centre, cityName: nil, checkedAt: checkedAt)
        #expect(result == .failure(.http(status: 503)))
    }

    @Test func aBodyThatIsNotAListOfRowsIsMalformed() async {
        let fetcher = RecordingFetcher { _ in Samples.response("{\"error\":\"nope\"}") }
        let source = NominatimPlacesSource(fetcher: fetcher, interval: .zero, sleep: { _ in })
        let result = await source.find(named: "Makars", near: centre, cityName: nil, checkedAt: checkedAt)
        #expect(result == .failure(.malformed("the Nominatim response")))
    }
}

struct NominatimRowTagsTests {
    @Test func theAddressComesFromTheRowWhenTheExtratagsHaveNone() throws {
        let json = """
        {"osm_type":"node","osm_id":301,"lat":"55.95","lon":"-3.20","category":"amenity","type":"place_of_worship",
         "name":"St Giles' Cathedral","extratags":{"wikidata":"Q1"},
         "address":{"house_number":"1","road":"High Street","city":"Edinburgh","postcode":"EH1 1RE"}}
        """
        let row = try JSONDecoder().decode(NominatimRow.self, from: Data(json.utf8))
        let tags = NominatimPlacesSource.tags(for: row, extra: NominatimPlacesSource.textTags(row.extratags))
        #expect(OSMPlaceMapper.address(in: tags) == "1 High Street, Edinburgh")
        #expect(OSMPlaceMapper.kind(for: tags) == .landmark)
    }
}
