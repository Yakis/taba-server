@testable import BuildKit
import Foundation
import ResponsesKit
import SourcesKit

/// Answers each request by its host, and keeps the requests it saw. No network is used.
actor ByHostFetcher: HTTPFetching {
    private let answer: @Sendable (URLRequest) -> HTTPResponse
    private(set) var requests: [URLRequest] = []

    init(answer: @escaping @Sendable (URLRequest) -> HTTPResponse) {
        self.answer = answer
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        return answer(request)
    }

    func count(host: String) -> Int {
        requests.filter { $0.url?.host == host }.count
    }
}

/// The evidence events a run wrote, in order.
actor EvidenceLog {
    private(set) var events: [[String: JSONValue]] = []

    func add(_ event: [String: JSONValue]) {
        events.append(event)
    }

    var names: [String] {
        events.compactMap { event in
            if case .string(let name)? = event["event"] { return name }
            return nil
        }
    }

    /// True when some event has this name and result, and, when `source` is given, that source too.
    func contains(event name: String, result: String, source: String?) -> Bool {
        events.contains { fields in
            guard case .string(let eventName)? = fields["event"], eventName == name,
                  case .string(let outcome)? = fields["result"], outcome == result
            else {
                return false
            }
            guard let source else { return true }
            if case .string(let origin)? = fields["source"] { return origin == source }
            return false
        }
    }
}

let overpassHost = "overpass-api.de"
let overpassBackupHost = "overpass.kumi.systems"
let nominatimHost = "nominatim.openstreetmap.org"
/// The Foursquare host. No build asks it any more, so every test checks that it gets no request.
let foursquareHost = "places-api.foursquare.com"

/// OpenStreetMap elements in the shape `out tags center` returns, written by hand. A music venue with hours, a park and
/// a cafe. Every Overpass query in these tests gets this answer unless a test says otherwise.
let overpassJSON = """
{"elements":[
  {"type":"node","id":7,"lat":55.95030,"lon":-3.20030,
   "tags":{"name":"The Venue Room","amenity":"music_venue","opening_hours":"Mo-Su 10:00-22:00"}},
  {"type":"node","id":8,"lat":55.95100,"lon":-3.20100,
   "tags":{"name":"Quiet Park","leisure":"park"}},
  {"type":"node","id":9,"lat":55.95110,"lon":-3.20110,
   "tags":{"name":"Corner Cafe","amenity":"cafe"}}
]}
"""

/// Nominatim rows for any phrase, written by hand in the jsonv2 shape with extratags. The same three places as the
/// Overpass answer, plus a chain and a car park that the sources must leave out.
let nominatimJSON = """
[
 {"osm_type":"node","osm_id":7,"lat":"55.95030","lon":"-3.20030","category":"amenity","type":"music_venue",
  "name":"The Venue Room","importance":0.2,"extratags":{"opening_hours":"Mo-Su 10:00-22:00"}},
 {"osm_type":"node","osm_id":8,"lat":"55.95100","lon":"-3.20100","category":"leisure","type":"park",
  "name":"Quiet Park","importance":0.1},
 {"osm_type":"node","osm_id":9,"lat":"55.95110","lon":"-3.20110","category":"amenity","type":"cafe",
  "name":"Corner Cafe","importance":0.1},
 {"osm_type":"node","osm_id":10,"lat":"55.95200","lon":"-3.20200","category":"amenity","type":"fast_food",
  "name":"Nando's","importance":0.9,"extratags":{"brand":"Nando's"}},
 {"osm_type":"node","osm_id":11,"lat":"55.95300","lon":"-3.20300","category":"amenity","type":"parking",
  "name":"Q-Park","importance":0.4}
]
"""

func reply(_ body: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, body: Data(body.utf8), headers: [:])
}

/// Overpass (both its servers) answers with `overpass`, and Nominatim with `nominatim`. Any other host, Foursquare
/// included, is refused with a 404, so a test that sends it a request sees the request as a failure.
func byHost(
    overpass: HTTPResponse = reply(overpassJSON),
    nominatim: HTTPResponse = reply(nominatimJSON)
) -> @Sendable (URLRequest) -> HTTPResponse {
    { request in
        switch request.url?.host {
        case nominatimHost: nominatim
        case overpassHost, overpassBackupHost: overpass
        default: reply("{}", status: 404)
        }
    }
}

/// The OpenStreetMap place sources with no waits: Overpass retries at once, and Nominatim is not paced.
func zeroWaits(_ fetcher: any HTTPFetching) -> OpenStreetMapPlaces {
    OpenStreetMapPlaces(
        overpass: OverpassPlacesSource(fetcher: fetcher, retryDelay: .zero, sleep: { _ in }),
        nominatim: NominatimPlacesSource(fetcher: fetcher, interval: .zero, sleep: { _ in })
    )
}
