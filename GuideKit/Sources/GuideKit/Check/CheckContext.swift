/// A booking that brings the traveller in or out of the trip. `stationPlaceId` is nil when the booking does not name
/// a place in the guide.
struct TransitTime {
    let time: LocalDateTime
    let stationPlaceId: String?
    /// True for a transport booking, false for the arrival or leaving time the traveller typed.
    var isBooking = true
}

/// Shared data for the checks, worked out once per guide.
struct CheckContext {
    let guide: Guide
    let walkTimes: any WalkTimes
    let arrival: TransitTime?
    let departure: TransitTime?
    /// The arrival and departure bookings, kept for the station checks.
    let arrivalBooking: Booking?
    let departureBooking: Booking?
    private let sunByDate: [LocalDate: SunTimes]

    init(guide: Guide, walkTimes: any WalkTimes) {
        self.guide = guide
        self.walkTimes = walkTimes
        let destination = guide.trip.destination
        var sun: [LocalDate: SunTimes] = [:]
        for day in guide.days {
            sun[day.date] = SunTimes.compute(
                date: day.date,
                at: destination.centre,
                timeZoneId: destination.timeZoneId
            )
        }
        self.sunByDate = sun

        let transit = guide.bookings.filter { [BookingKind.train, .flight, .bus].contains($0.kind) }
        let arrivalBooking = transit
            .filter { $0.arrives.date == guide.trip.dates.start }
            .min { $0.arrives < $1.arrives }
        let departureBooking = transit
            .filter { $0.departs.date == guide.trip.dates.end }
            .min { $0.departs < $1.departs }
        self.arrivalBooking = arrivalBooking
        self.departureBooking = departureBooking
        let dates = guide.trip.dates
        // A booking wins over the times the traveller typed.
        self.arrival = arrivalBooking.map { TransitTime(time: $0.arrives, stationPlaceId: $0.toPlaceId) }
            ?? dates.arrives.map {
                TransitTime(time: LocalDateTime(date: dates.start, time: $0), stationPlaceId: nil, isBooking: false)
            }
        self.departure = departureBooking.map { TransitTime(time: $0.departs, stationPlaceId: $0.fromPlaceId) }
            ?? dates.leaves.map {
                TransitTime(time: LocalDateTime(date: dates.end, time: $0), stationPlaceId: nil, isBooking: false)
            }
    }

    func place(_ id: String?) -> Place? {
        guard let id else { return nil }
        return guide.places[id]
    }

    func sunTimes(on date: LocalDate) -> SunTimes? {
        sunByDate[date]
    }

    func day(on date: LocalDate) -> Day? {
        guide.days.first { $0.date == date }
    }

    /// The leg between two stops' places, or nil when either stop has no place.
    func stopLeg(_ first: String?, _ second: String?) -> Leg? {
        guard let firstPlace = place(first), let secondPlace = place(second) else { return nil }
        return leg(firstPlace, secondPlace)
    }

    /// The walk, or bus or taxi ride, between two places.
    func leg(_ first: Place, _ second: Place) -> Leg {
        Travel.leg(from: first.location.coordinate, to: second.location.coordinate, walkTimes: walkTimes)
    }

    /// The place's name, or the stop's title when the stop has no place.
    func label(_ stop: Stop) -> String {
        place(stop.placeId)?.name ?? stop.copy.title
    }
}
