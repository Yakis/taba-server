import Foundation

/// The inputs to a place search: an optional name, a point and radius, optional categories, and a limit.
public struct SearchParameters: Sendable, Hashable {
    public let query: String?
    public let latitude: Double
    public let longitude: Double
    public let radius: Int
    public let categoryIds: [String]
    public let limit: Int

    public init(
        query: String?,
        latitude: Double,
        longitude: Double,
        radius: Int,
        categoryIds: [String],
        limit: Int
    ) {
        self.query = query
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.categoryIds = categoryIds
        self.limit = limit
    }
}

/// Builds Places API requests. The key is sent only in the Authorization header. This type never prints it.
public struct FoursquareRequestBuilder: Sendable, CustomStringConvertible {
    public static let host = "places-api.foursquare.com"
    /// The X-Places-Api-Version value the probe is written against.
    public static let apiVersion = "2025-06-17"

    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public var description: String {
        "FoursquareRequestBuilder(apiKey: <redacted>)"
    }

    /// GET /places/search, sorted by distance, within the radius of the point.
    public func search(_ parameters: SearchParameters) -> URLRequest {
        var items = [
            URLQueryItem(name: "ll", value: "\(parameters.latitude),\(parameters.longitude)"),
            URLQueryItem(name: "radius", value: String(parameters.radius)),
            URLQueryItem(name: "limit", value: String(parameters.limit))
        ]
        if let query = parameters.query, !query.isEmpty {
            items.append(URLQueryItem(name: "query", value: query))
        }
        if !parameters.categoryIds.isEmpty {
            let ids = parameters.categoryIds.joined(separator: ",")
            items.append(URLQueryItem(name: "fsq_category_ids", value: ids))
        }
        return makeRequest(path: "/places/search", items: items)
    }

    /// GET /places/{fsq_place_id} with the listed fields.
    public func details(fsqPlaceId: String, fields: [String]) -> URLRequest {
        makeRequest(
            path: "/places/\(fsqPlaceId)",
            items: [URLQueryItem(name: "fields", value: fields.joined(separator: ","))]
        )
    }

    private func makeRequest(path: String, items: [URLQueryItem]) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = path
        components.queryItems = items
        guard let url = components.url else {
            preconditionFailure("Places API path is not a valid URL: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-Places-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
