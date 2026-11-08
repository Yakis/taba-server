/// The search response: `results` is the list of places, nearest first.
public struct FoursquareSearchResponse: Decodable, Sendable {
    public let results: [FoursquarePlace]
}

/// A place as the Places API returns it. Only the fields the probe reads are modelled. A section that fails to
/// decode is dropped instead of failing the whole response, so the probe can report what came back.
public struct FoursquarePlace: Decodable, Sendable, Hashable {
    public let fsqPlaceId: String
    public let name: String
    public let latitude: Double?
    public let longitude: Double?
    public let location: FoursquareLocation?
    public let categories: [FoursquareCategory]
    public let dateClosed: String?
    public let hours: FoursquareHours?
    public let rating: Double?
    public let website: String?

    enum CodingKeys: String, CodingKey {
        case fsqPlaceId = "fsq_place_id"
        case name
        case latitude
        case longitude
        case location
        case categories
        case dateClosed = "date_closed"
        case hours
        case rating
        case website
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fsqPlaceId = try container.decode(String.self, forKey: .fsqPlaceId)
        name = try container.decode(String.self, forKey: .name)
        latitude = try? container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? container.decodeIfPresent(Double.self, forKey: .longitude)
        location = try? container.decodeIfPresent(FoursquareLocation.self, forKey: .location)
        categories = (try? container.decodeIfPresent([FoursquareCategory].self, forKey: .categories)) ?? []
        dateClosed = try? container.decodeIfPresent(String.self, forKey: .dateClosed)
        hours = try? container.decodeIfPresent(FoursquareHours.self, forKey: .hours)
        rating = try? container.decodeIfPresent(Double.self, forKey: .rating)
        website = try? container.decodeIfPresent(String.self, forKey: .website)
    }
}

public struct FoursquareLocation: Decodable, Sendable, Hashable {
    public let address: String?
    public let formattedAddress: String?
    public let locality: String?
    public let postcode: String?
    public let country: String?

    enum CodingKeys: String, CodingKey {
        case address
        case formattedAddress = "formatted_address"
        case locality
        case postcode
        case country
    }
}

public struct FoursquareCategory: Decodable, Sendable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id = "fsq_category_id"
        case name
    }
}

/// Opening hours from a details request. `regular` holds one entry per open period.
public struct FoursquareHours: Decodable, Sendable, Hashable {
    public let display: String?
    public let openNow: Bool?
    public let regular: [FoursquareRegularHours]

    enum CodingKeys: String, CodingKey {
        case display
        case openNow = "open_now"
        case regular
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        display = try? container.decodeIfPresent(String.self, forKey: .display)
        openNow = try? container.decodeIfPresent(Bool.self, forKey: .openNow)
        regular = (try? container.decodeIfPresent([FoursquareRegularHours].self, forKey: .regular)) ?? []
    }
}

/// One open period. `day` runs 1 (Monday) to 7 (Sunday). `open` and `close` are "HHMM".
public struct FoursquareRegularHours: Decodable, Sendable, Hashable {
    public let day: Int
    public let open: String
    public let close: String
}

/// The error body: `{"message": "..."}`. The message may be absent.
public struct FoursquareErrorBody: Decodable, Sendable {
    public let message: String?
}
