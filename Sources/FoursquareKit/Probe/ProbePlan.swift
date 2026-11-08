import GuideKit

/// A fixture place to search for.
public struct SearchTarget: Sendable, Hashable {
    public let fixtureId: String
    public let name: String
    public let kind: PlaceKind
    public let coordinate: Coordinate

    public init(fixtureId: String, name: String, kind: PlaceKind, coordinate: Coordinate) {
        self.fixtureId = fixtureId
        self.name = name
        self.kind = kind
        self.coordinate = coordinate
    }
}

/// Which places to search, and how a search's top hit is judged.
public enum ProbePlan {
    public static let searchRadiusMetres = 300
    public static let searchLimit = 3
    public static let matchDistanceMetres = 150.0
    public static let sweepRadiusMetres = 1500
    public static let sweepLimit = 50
    public static let premiumLimit = 25
    public static let requestLimit = 60
    public static let pauseMilliseconds = 200
    public static let premiumFields = ["hours", "rating"]

    /// Kinds that are not searched: stays, luggage stores and stations are not Foursquare's kind of place.
    public static let excludedKinds: Set<PlaceKind> = [.lodging, .luggage, .station]

    /// Fixture places to search, sorted by id. Hand-entered ids ("manual:") are skipped.
    public static func searchTargets(in guide: Guide) -> [SearchTarget] {
        guide.places.values
            .filter { !excludedKinds.contains($0.kind) && !$0.id.hasPrefix("manual:") }
            .sorted { $0.id < $1.id }
            .map { SearchTarget(fixtureId: $0.id, name: $0.name, kind: $0.kind, coordinate: $0.location.coordinate) }
    }

    /// Judges a search. The top hit matches when its name matches the fixture name and it lies within 150 m.
    public static func evaluate(target: SearchTarget, hits: [FoursquarePlace]) -> PlaceProbe {
        guard let top = hits.first else {
            return PlaceProbe(
                fixtureId: target.fixtureId,
                fixtureName: target.name,
                fixtureKind: target.kind,
                hitCount: 0,
                topHit: nil,
                matched: false,
                error: nil
            )
        }
        let distance = distanceMetres(from: target.coordinate, to: top)
        let hit = TopHit(
            fsqPlaceId: top.fsqPlaceId,
            name: top.name,
            distanceMetres: distance.map { Int($0.rounded()) },
            categoryNames: top.categories.map(\.name),
            fieldsReturned: FieldReport.returnedFields(in: top)
        )
        let nameMatches = NameMatch.matches(target.name, top.name)
        let isClose = (distance ?? .infinity) < matchDistanceMetres
        return PlaceProbe(
            fixtureId: target.fixtureId,
            fixtureName: target.name,
            fixtureKind: target.kind,
            hitCount: hits.count,
            topHit: hit,
            matched: nameMatches && isClose,
            error: nil
        )
    }

    static func distanceMetres(from coordinate: Coordinate, to place: FoursquarePlace) -> Double? {
        guard let latitude = place.latitude, let longitude = place.longitude,
              let other = Coordinate(latitude: latitude, longitude: longitude)
        else {
            return nil
        }
        return Geo.metres(from: coordinate, to: other)
    }
}

/// Lists which response fields a place actually carries, so the report can show what came back.
public enum FieldReport {
    public static func returnedFields(in place: FoursquarePlace) -> [String] {
        var fields: [String] = []
        if place.latitude != nil { fields.append("latitude") }
        if place.longitude != nil { fields.append("longitude") }
        fields += locationFields(place.location)
        if !place.categories.isEmpty { fields.append("categories") }
        if place.dateClosed != nil { fields.append("date_closed") }
        if place.hours != nil { fields.append("hours") }
        if place.rating != nil { fields.append("rating") }
        return fields
    }

    private static func locationFields(_ location: FoursquareLocation?) -> [String] {
        guard let location else { return [] }
        var fields: [String] = []
        if location.address != nil { fields.append("location.address") }
        if location.formattedAddress != nil { fields.append("location.formatted_address") }
        if location.locality != nil { fields.append("location.locality") }
        if location.postcode != nil { fields.append("location.postcode") }
        return fields
    }
}
