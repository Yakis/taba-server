/// A booking that brings the traveller in or out of the trip. `stationPlaceId` is nil when the booking does not name
/// a place in the guide.
struct TransitTime {
    let time: LocalDateTime
    let stationPlaceId: String?
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
        self.arrival = arrivalBooking.map { TransitTime(time: $0.arrives, stationPlaceId: $0.toPlaceId) }
        self.departure = departureBooking.map { TransitTime(time: $0.departs, stationPlaceId: $0.fromPlaceId) }
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

    /// Walking minutes between two stops' places, or nil when either stop has no place.
    func stopWalkMinutes(_ first: String?, _ second: String?) -> Int? {
        guard let firstPlace = place(first), let secondPlace = place(second) else { return nil }
        return walkMinutes(firstPlace, secondPlace)
    }

    func walkMinutes(_ first: Place, _ second: Place) -> Int {
        walkTimes.minutes(from: first.location.coordinate, to: second.location.coordinate)
    }

    /// The place's name, or the stop's title when the stop has no place.
    func label(_ stop: Stop) -> String {
        place(stop.placeId)?.name ?? stop.copy.title
    }
}
