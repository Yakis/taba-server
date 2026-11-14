import Foundation
import GuideKit
@testable import SourcesKit
import Testing

/// Names for the shortened-query cases, and the query each should shorten to (nil when it cannot shorten).
private let shortenedNames = [
    "Whitelock's Ale House", "The Corn Exchange", "Kirkgate Market", "Belgrave Music Hall", "Whitelocks",
    "The Hall", "North Bar Leeds"
]
private let shortenedQueries: [String?] = [
    "Whitelocks", "Corn Exchange", "Kirkgate", "Belgrave Music", nil, "Hall", "North"
]

/// The shorter second search of `NominatimPlacesSource.find`, which runs when the full name has no match. These tests
/// sit apart from `NominatimPlacesSourceTests` to keep each file within SwiftLint's length limits.
struct NominatimShortenedNameTests {
    private let checkedAt = Samples.date("2026-11-14")
    private let centre = Samples.coordinate(55.9500, -3.2000)

    /// A source whose answers come from `rows`, keyed by the query, with "[]" for any other query. Queries in
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

    @Test(arguments: zip(shortenedNames, shortenedQueries))
    func shorterQueryDropsDecorationsAndKeepsAtLeastOneWord(name: String, expected: String?) {
        #expect(NominatimPlacesSource.shorterQuery(name, cityName: "Leeds") == expected)
    }

    @Test func shorterQueryKeepsACityWordOnlyWhenNoCityIsGiven() {
        #expect(NominatimPlacesSource.shorterQuery("North Bar Leeds", cityName: nil) == nil)
    }

    @Test func aFullNameMatchIsSearchedOnce() async throws {
        let rows = """
        [{"osm_type":"node","osm_id":1001,"lat":"55.9500","lon":"-3.2000","category":"amenity","type":"pub",
          "name":"Whitelock's Ale House"}]
        """
        let (source, fetcher) = makeSource(rows: ["Whitelock's Ale House": rows])
        let found = try #require(try await source.find(named: "Whitelock's Ale House", near: centre,
                                                       cityName: "Edinburgh", checkedAt: checkedAt).get())
        #expect(found.id == "osm:node/1001")
        #expect(await fetcher.requests.count == 1)
    }

    @Test func aNoMatchRetriesWithTheShorterNameAndFindsThePub() async throws {
        let rows = """
        [{"osm_type":"node","osm_id":1002,"lat":"55.9500","lon":"-3.2000","category":"amenity","type":"pub",
          "name":"Whitelock's Ale House"}]
        """
        let (source, fetcher) = makeSource(rows: ["Whitelocks": rows])
        let found = try #require(try await source.find(named: "Whitelock's Ale House", near: centre,
                                                       cityName: "Edinburgh", checkedAt: checkedAt).get())
        #expect(found.id == "osm:node/1002")
        let requests = await fetcher.requests
        #expect(requests.count == 2)
        #expect(requests.map { Samples.query($0)["q"] } == ["Whitelock's Ale House", "Whitelocks"])
    }

    @Test func aNameThatCannotBeShortenedIsSearchedOnceWithNoMatch() async throws {
        let (source, fetcher) = makeSource(rows: [:])
        let result = await source.find(named: "Makars", near: centre, cityName: nil, checkedAt: checkedAt)
        #expect(try result.get() == nil)
        #expect(await fetcher.requests.count == 1)
    }

    @Test func aShortenedNameNeverMatchesAStreetOrPlace() async throws {
        let rows = """
        [{"osm_type":"way","osm_id":1101,"lat":"55.9500","lon":"-3.2000","category":"highway","type":"pedestrian",
          "name":"Kirkgate"}]
        """
        let (source, fetcher) = makeSource(rows: ["Kirkgate": rows])
        let result = await source.find(named: "Kirkgate Market", near: centre, cityName: "Leeds",
                                       checkedAt: checkedAt)
        #expect(try result.get() == nil)
        let requests = await fetcher.requests
        #expect(requests.map { Samples.query($0)["q"] } == ["Kirkgate Market", "Kirkgate"])
    }

    @Test func aRetryRowNamedExactlyTheShortFormIsFound() async throws {
        let rows = """
        [{"osm_type":"node","osm_id":1201,"lat":"55.9500","lon":"-3.2000","category":"amenity","type":"pub",
          "name":"Whitelocks"}]
        """
        let (source, _) = makeSource(rows: ["Whitelocks": rows])
        let found = try #require(try await source.find(named: "Whitelock's Ale House", near: centre,
                                                       cityName: "Edinburgh", checkedAt: checkedAt).get())
        #expect(found.id == "osm:node/1201")
    }

    @Test func aFailedRetryIsAFailure() async {
        let fetcher = RecordingFetcher { request in
            Samples.query(request)["q"] == "Whitelocks" ? Samples.response("", status: 500) : Samples.response("[]")
        }
        let source = NominatimPlacesSource(fetcher: fetcher, interval: .zero, sleep: { _ in })
        let result = await source.find(named: "Whitelock's Ale House", near: centre,
                                       cityName: "Edinburgh", checkedAt: checkedAt)
        #expect(result == .failure(.http(status: 500)))
        #expect(await fetcher.requests.count == 2)
    }
}
