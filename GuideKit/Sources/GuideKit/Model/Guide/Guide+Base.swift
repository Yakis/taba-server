/// The place a guide measures distances from: the stay the traveller named or, on a one-day trip without one, where
/// they arrive. Never a place the guide made up.
public struct GuideBase: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The stay the traveller named.
        case stay
        /// Where the traveller arrives on a one-day trip, reached by this mode.
        case arrival(TravelMode)
    }

    public let place: Place
    public let kind: Kind

    public init(place: Place, kind: Kind) {
        self.place = place
        self.kind = kind
    }

    /// How the guide names the base in "6 min from the station": "the stay", "the station", "the coach station",
    /// "the airport" or "where you park".
    public var phrase: String {
        switch kind {
        case .stay: "the stay"
        case .arrival(.train): "the station"
        case .arrival(.coach): "the coach station"
        case .arrival(.flight): "the airport"
        case .arrival(.car): "where you park"
        }
    }
}

extension GuideBase {
    /// Whether the travellers have a stay the guide knows about, from the stay, the trip and its places. Stays
    /// recorded before `arrangement` existed say it through their place: the old unbooked placeholder
    /// (`manual:stay` at an approximate spot) was never a real stay.
    public static func arrangement(stay: Stay, trip: Trip, places: [String: Place]) -> StayArrangement {
        if let arrangement = stay.arrangement {
            return arrangement
        }
        if let id = stay.placeId, let place = places[id],
           !(id == legacyPlaceholderStayId && place.location.approximate) {
            return .booked
        }
        return trip.dates.start == trip.dates.end ? .notNeeded : .unknown
    }

    /// The place distances are measured from: the stay the traveller named or, on a one-day trip without one, where
    /// they arrive (the place they said, or the arrival booking's station). Nil when there is none.
    public static func resolve(stay: Stay, trip: Trip, bookings: [Booking], places: [String: Place]) -> GuideBase? {
        if arrangement(stay: stay, trip: trip, places: places) == .booked, let id = stay.placeId,
           let place = places[id] {
            return GuideBase(place: place, kind: .stay)
        }
        guard trip.dates.start == trip.dates.end else { return nil }
        if let travel = trip.travel, let id = travel.arrivalPlaceId, let place = places[id] {
            return GuideBase(place: place, kind: .arrival(travel.mode))
        }
        let arrival = bookings
            .filter { [BookingKind.train, .flight, .bus].contains($0.kind) && $0.arrives.date == trip.dates.start }
            .min { $0.arrives < $1.arrives }
        guard let arrival, let id = arrival.toPlaceId, let place = places[id] else { return nil }
        let mode: TravelMode = switch arrival.kind {
        case .flight: .flight
        case .bus: .coach
        default: .train
        }
        return GuideBase(place: place, kind: .arrival(mode))
    }

    /// The id the server gave the placeholder base of an unbooked trip before stays were recorded.
    static let legacyPlaceholderStayId = "manual:stay"
}

extension Guide {
    /// True when the trip starts and ends on the same date, so it has no night.
    public var isOneDay: Bool {
        trip.dates.start == trip.dates.end
    }

    /// Whether the travellers have a stay the guide knows about. See `GuideBase.arrangement`.
    public var stayArrangement: StayArrangement {
        GuideBase.arrangement(stay: stay, trip: trip, places: places)
    }

    /// The stay's place, only when the traveller named one. Nil for an unknown or unneeded stay, even in old guides
    /// that carry a placeholder.
    public var stayPlace: Place? {
        guard stayArrangement == .booked, let id = stay.placeId else { return nil }
        return places[id]
    }

    /// True when `placeId` is the place of a stay the traveller named.
    public func isStayPlace(_ placeId: String?) -> Bool {
        stayPlace.map { $0.id == placeId } ?? false
    }

    /// The place distances are measured from, or nil when there is none: then the guide shows no "from the stay".
    public var base: GuideBase? {
        GuideBase.resolve(stay: stay, trip: trip, bookings: bookings, places: places)
    }
}

extension TripFacts {
    /// Whether the travellers have a stay the guide knows about. See `GuideBase.arrangement`.
    public var stayArrangement: StayArrangement {
        GuideBase.arrangement(stay: stay, trip: trip, places: places)
    }

    /// The place distances are measured from, or nil. The same rule as `Guide.base`.
    public var base: GuideBase? {
        GuideBase.resolve(stay: stay, trip: trip, bookings: bookings, places: places)
    }
}
