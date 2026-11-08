import Foundation
import GuideKit

/// A place found by name.
public struct GeocodedPlace: Sendable, Equatable {
    public let coordinate: Coordinate
    public let displayName: String
    /// Two-letter ISO code in upper case, when the search gave one.
    public let countryCode: String?
}

/// Nominatim geocoding: a name to a centre, and a point to its neighbourhood.
///
/// Every request waits for the pacer first. The public policy allows one request per second, so the default pacer
/// does too. Tests inject a clock and a sleeper.
public struct NominatimGeocoder: Sendable {
    public static let host = "nominatim.openstreetmap.org"
    /// The zoom level for an area name: neighbourhood, suburb or quarter.
    public static let areaZoom = 15
    private static let areaKeys = ["neighbourhood", "suburb", "quarter"]

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

    /// The first match for `query`, or nil when Nominatim finds nothing.
    public func geocode(_ query: String) async throws -> GeocodedPlace? {
        let items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "accept-language", value: "en")
        ]
        let response = try await send(path: "/search", items: items)
        let hits = try decode([NominatimSearchHit].self, from: response)
        guard let first = hits.first,
              let latitude = Double(first.lat),
              let longitude = Double(first.lon),
              let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        else {
            return nil
        }
        let countryCode = first.address?["country_code"]?.text?.uppercased()
        return GeocodedPlace(coordinate: coordinate, displayName: first.displayName, countryCode: countryCode)
    }

    /// The neighbourhood, suburb or quarter name at a point, or nil when there is none, or nothing is found there.
    public func areaName(near coordinate: Coordinate) async throws -> String? {
        let items = [
            URLQueryItem(name: "lat", value: String(format: "%.6f", coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.6f", coordinate.longitude)),
            URLQueryItem(name: "zoom", value: String(Self.areaZoom)),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "accept-language", value: "en")
        ]
        let response = try await send(path: "/reverse", items: items)
        if response.status == 404 {
            return nil
        }
        let result = try decode(NominatimReverseResponse.self, from: response)
        guard let address = result.address else { return nil }
        for key in Self.areaKeys {
            if let name = address[key]?.text, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private func send(path: String, items: [URLQueryItem]) async throws -> HTTPResponse {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = path
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
        guard response.isSuccess || response.status == 404 else {
            throw SourcesError.http(status: response.status)
        }
        return response
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from response: HTTPResponse) throws -> Value {
        guard response.isSuccess else {
            throw SourcesError.http(status: response.status)
        }
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw SourcesError.malformed("the Nominatim response")
        }
    }
}

/// One Nominatim search hit in `jsonv2` format. Latitude and longitude are strings there.
struct NominatimSearchHit: Decodable {
    let lat: String
    let lon: String
    let displayName: String
    let address: [String: LossyText]?

    enum CodingKeys: String, CodingKey {
        case lat
        case lon
        case displayName = "display_name"
        case address
    }
}

struct NominatimReverseResponse: Decodable {
    let address: [String: LossyText]?
}

/// A string value from an address map. Any other JSON type reads as nil rather than failing the whole response.
struct LossyText: Decodable {
    let text: String?

    init(from decoder: any Decoder) throws {
        text = try? decoder.singleValueContainer().decode(String.self)
    }
}
