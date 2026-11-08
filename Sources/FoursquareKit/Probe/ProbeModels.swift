import GuideKit

/// A failed request. `status` is nil for a network failure. `message` is Foursquare's own error text, if it sent one.
public struct ProbeError: Sendable, Hashable {
    public let status: Int?
    public let message: String?
    public let detail: String

    public init(status: Int?, message: String?, detail: String) {
        self.status = status
        self.message = message
        self.detail = detail
    }
}

/// The top search hit for a fixture place.
public struct TopHit: Sendable, Hashable {
    public let fsqPlaceId: String
    public let name: String
    public let distanceMetres: Int?
    public let categoryNames: [String]
    public let fieldsReturned: [String]

    public init(
        fsqPlaceId: String,
        name: String,
        distanceMetres: Int?,
        categoryNames: [String],
        fieldsReturned: [String]
    ) {
        self.fsqPlaceId = fsqPlaceId
        self.name = name
        self.distanceMetres = distanceMetres
        self.categoryNames = categoryNames
        self.fieldsReturned = fieldsReturned
    }
}

/// The result of searching for one fixture place.
public struct PlaceProbe: Sendable, Hashable {
    public let fixtureId: String
    public let fixtureName: String
    public let fixtureKind: PlaceKind
    public let hitCount: Int
    public let topHit: TopHit?
    public let matched: Bool
    public let error: ProbeError?

    public init(
        fixtureId: String,
        fixtureName: String,
        fixtureKind: PlaceKind,
        hitCount: Int,
        topHit: TopHit?,
        matched: Bool,
        error: ProbeError?
    ) {
        self.fixtureId = fixtureId
        self.fixtureName = fixtureName
        self.fixtureKind = fixtureKind
        self.hitCount = hitCount
        self.topHit = topHit
        self.matched = matched
        self.error = error
    }
}

/// The result of one category sweep around the destination centre.
public struct SweepResult: Sendable, Hashable {
    public let sweep: CategorySweep
    public let resultCount: Int
    public let topNames: [String]
    public let error: ProbeError?

    public init(sweep: CategorySweep, resultCount: Int, topNames: [String], error: ProbeError?) {
        self.sweep = sweep
        self.resultCount = resultCount
        self.topNames = topNames
        self.error = error
    }
}

/// The result of a details request for a matched place, with the fields it asked for.
public struct PremiumResult: Sendable, Hashable {
    public let fixtureId: String
    public let fsqPlaceId: String
    public let regularEntries: Int
    public let entriesWithAllFields: Int
    public let display: String?
    public let openNow: Bool?
    public let rating: Double?
    public let error: ProbeError?

    public init(
        fixtureId: String,
        fsqPlaceId: String,
        regularEntries: Int,
        entriesWithAllFields: Int,
        display: String?,
        openNow: Bool?,
        rating: Double?,
        error: ProbeError?
    ) {
        self.fixtureId = fixtureId
        self.fsqPlaceId = fsqPlaceId
        self.regularEntries = regularEntries
        self.entriesWithAllFields = entriesWithAllFields
        self.display = display
        self.openNow = openNow
        self.rating = rating
        self.error = error
    }
}
