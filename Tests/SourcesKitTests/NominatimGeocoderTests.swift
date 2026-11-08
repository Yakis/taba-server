import Foundation
import GuideKit
import SourcesKit
import Testing

struct NominatimGeocoderTests {
    private let edinburghHit = """
    [{"place_id":1,"lat":"55.9533","lon":"-3.1883",
      "display_name":"Edinburgh, City of Edinburgh, Scotland, United Kingdom",
      "address":{"city":"Edinburgh","country":"United Kingdom","country_code":"gb"}}]
    """

    private func makeGeocoder(
        answer: @escaping @Sendable (URLRequest) -> HTTPResponse,
        clock: FakeClock = FakeClock()
    ) -> (NominatimGeocoder, RecordingFetcher) {
        let fetcher = RecordingFetcher(answer: answer)
        let geocoder = NominatimGeocoder(
            fetcher: fetcher,
            interval: .seconds(1),
            now: { clock.now },
            sleep: { clock.sleep($0) }
        )
        return (geocoder, fetcher)
    }

    @Test func aNameBecomesACentreWithADisplayNameAndCountryCode() async throws {
        let (geocoder, fetcher) = makeGeocoder(answer: { _ in Samples.response(self.edinburghHit) })
        let place = try #require(try await geocoder.geocode("Edinburgh"))
        #expect(place.coordinate == Samples.coordinate(55.9533, -3.1883))
        #expect(place.displayName.hasPrefix("Edinburgh, City of Edinburgh"))
        #expect(place.countryCode == "GB")
        let request = try #require(await fetcher.requests.first)
        #expect(request.url?.host == "nominatim.openstreetmap.org")
        #expect(request.url?.path == "/search")
        #expect(Samples.query(request)["format"] == "jsonv2")
        #expect(Samples.query(request)["q"] == "Edinburgh")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "TABA/0.1 (personal travel guide)")
    }

    @Test func aNameWithNoResultsGivesNothing() async throws {
        let (geocoder, _) = makeGeocoder(answer: { _ in Samples.response("[]") })
        #expect(try await geocoder.geocode("Nowhere in particular") == nil)
    }

    @Test func aNeighbourhoodIsPreferredAsTheAreaName() async throws {
        let body = """
        {"place_id":2,"lat":"55.9590","lon":"-3.2100",
         "display_name":"Stockbridge, Edinburgh, Scotland",
         "address":{"neighbourhood":"Stockbridge","suburb":"New Town","country_code":"gb"}}
        """
        let (geocoder, fetcher) = makeGeocoder(answer: { _ in Samples.response(body) })
        let area = try await geocoder.areaName(near: Samples.coordinate(55.9590, -3.2100))
        #expect(area == "Stockbridge")
        let request = try #require(await fetcher.requests.first)
        #expect(request.url?.path == "/reverse")
        #expect(Samples.query(request)["zoom"] == "15")
    }

    @Test func aSuburbIsUsedWhenThereIsNoNeighbourhood() async throws {
        let body = #"{"address":{"suburb":"Bruntsfield","country_code":"gb"}}"#
        let (geocoder, _) = makeGeocoder(answer: { _ in Samples.response(body) })
        #expect(try await geocoder.areaName(near: Samples.coordinate(55.94, -3.21)) == "Bruntsfield")
    }

    @Test func aPointWithNoAreaNameGivesNothing() async throws {
        let body = #"{"address":{"road":"Victoria Street","country_code":"gb"}}"#
        let (geocoder, _) = makeGeocoder(answer: { _ in Samples.response(body) })
        #expect(try await geocoder.areaName(near: Samples.coordinate(55.95, -3.20)) == nil)
    }

    @Test func aNotFoundReverseLookupGivesNothing() async throws {
        let (geocoder, _) = makeGeocoder(answer: { _ in
            Samples.response(#"{"error":"Unable to geocode"}"#, status: 404)
        })
        #expect(try await geocoder.areaName(near: Samples.coordinate(0.5, 0.5)) == nil)
    }

    @Test func aNonTextAddressValueDoesNotStopTheAreaName() async throws {
        let body = #"{"address":{"house_number":12,"quarter":"Leith","country_code":"gb"}}"#
        let (geocoder, _) = makeGeocoder(answer: { _ in Samples.response(body) })
        #expect(try await geocoder.areaName(near: Samples.coordinate(55.97, -3.17)) == "Leith")
    }

    @Test func aServerErrorIsAnError() async {
        let (geocoder, _) = makeGeocoder(answer: { _ in Samples.response("", status: 503) })
        await #expect(throws: SourcesError.http(status: 503)) {
            try await geocoder.geocode("Edinburgh")
        }
    }

    @Test func requestsAreSpacedOneSecondApart() async throws {
        let clock = FakeClock()
        let (geocoder, _) = makeGeocoder(
            answer: { request in
                let isSearch = request.url?.path == "/search"
                return Samples.response(isSearch ? self.edinburghHit : "{\"address\":{\"suburb\":\"Leith\"}}")
            },
            clock: clock
        )
        _ = try await geocoder.geocode("Edinburgh")
        _ = try await geocoder.areaName(near: Samples.coordinate(55.97, -3.17))
        _ = try await geocoder.areaName(near: Samples.coordinate(55.94, -3.21))
        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
    }
}
