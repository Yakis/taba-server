import Foundation
import GuideKit
@testable import SourcesKit
import Testing

struct OverpassFindTests {
    private let checkedAt = Samples.date("2026-11-14")
    private let centre = Samples.coordinate(55.9500, -3.2000)

    /// The Overpass query a request carried, decoded from its form body.
    private func queryText(_ request: URLRequest) -> String {
        let body = request.httpBody.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        let encoded = body.hasPrefix("data=") ? String(body.dropFirst(5)) : body
        return encoded.removingPercentEncoding ?? ""
    }

    // MARK: Find

    private func findAnswer(_ elements: String) -> String {
        "{\"elements\":[" + elements + "]}"
    }

    @Test func findPicksTheMostSimilarName() async throws {
        let answer = findAnswer("""
        {"type":"node","id":501,"lat":55.9510,"lon":-3.2010,"tags":{"name":"Oink"}},
        {"type":"node","id":502,"lat":55.9500,"lon":-3.2000,"tags":{"name":"Makars"}},
        {"type":"node","id":503,"lat":55.9400,"lon":-3.2300,"tags":{"name":"Makars Mash House","amenity":"pub"}}
        """)
        let fetcher = ScriptedFetcher([.respond(Samples.response(answer))])
        let source = OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in })
        let result = await source.find(named: "Makars Mash Bar", near: centre, cityName: "Edinburgh",
                                       checkedAt: checkedAt)
        let found = try #require(try result.get())
        #expect(found.id == "osm:node/503")
        #expect(found.kind == .pub)
        let text = await fetcher.requests.first.map(queryText) ?? ""
        #expect(text.contains(
            "nwr[\"name\"~\"makar['’]?s\",i][\"name\"~\"mash\",i](around:10000,55.950000,-3.200000);"))
        #expect(text.hasSuffix("out tags center 30;"))
    }

    @Test func findTiesGoToTheNearest() async throws {
        let answer = findAnswer("""
        {"type":"node","id":601,"lat":55.9600,"lon":-3.2000,"tags":{"name":"Makars Mash Bar"}},
        {"type":"node","id":602,"lat":55.9505,"lon":-3.2005,"tags":{"name":"Makars Mash Bar"}}
        """)
        let fetcher = ScriptedFetcher([.respond(Samples.response(answer))])
        let source = OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in })
        let found = try #require(try await source.find(named: "Makars Mash Bar", near: centre, cityName: nil,
                                                       checkedAt: checkedAt).get())
        #expect(found.id == "osm:node/602")
    }

    @Test func findReturnsNothingBelowTheSimilarityThreshold() async throws {
        let answer = findAnswer("""
        {"type":"node","id":701,"lat":55.9500,"lon":-3.2000,"tags":{"name":"Harbour Fish Market"}}
        """)
        let fetcher = ScriptedFetcher([.respond(Samples.response(answer))])
        let source = OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in })
        let result = await source.find(named: "Harbour Lights Club", near: centre, cityName: "Edinburgh",
                                       checkedAt: checkedAt)
        #expect(try result.get() == nil)
    }

    @Test func findSendsNoRequestWithoutASignificantWord() async throws {
        let fetcher = ScriptedFetcher([])
        let source = OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in })
        let result = await source.find(named: "  ", near: centre, cityName: "Edinburgh", checkedAt: checkedAt)
        #expect(try result.get() == nil)
        #expect(await fetcher.requests.isEmpty)
    }

    @Test func findEscapesTheCharactersARegexWouldRead() {
        #expect(OverpassPlacesSource.escapedRegex("a.b(c)\"d\\") == "a\\.b\\(c\\)\\\"d\\\\")
        #expect(OverpassPlacesSource.escapedRegex("plain") == "plain")
        #expect(OverpassPlacesSource.escapedRegex("x*+?[]{}^$|") == "x\\*\\+\\?\\[\\]\\{\\}\\^\\$\\|")
    }
}
