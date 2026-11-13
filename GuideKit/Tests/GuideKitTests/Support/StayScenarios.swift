import GuideKit

/// Made-up trips for the stay tests. The town is called Testford, and its places are a station, a cafe, a hotel, an
/// inn, a luggage store and a museum. Nothing here is a real place, booking or stay.
enum StayScenarios {
    static let stationId = "manual:testford-station"
    static let cafeId = "manual:testford-cafe"
    static let hotelId = "manual:testford-hotel"
    static let innId = "manual:testford-inn"
    static let storeId = "manual:testford-store"
    static let museumId = "manual:testford-museum"
    static let marketId = "osm:testford-market"

    static let centre = SampleGuide.coordinate(52.0000, -1.5000)

    /// A stay with no place, no times and no night: the traveller named nowhere to sleep on a day trip.
    static let noStay = Stay(placeId: nil, checkIn: nil, checkOut: nil, luggage: nil, arrangement: .notNeeded)

    // MARK: Trips

    static func trip(
        start: String,
        end: String,
        travel: TripTravel? = nil,
        arrives: String? = nil,
        leaves: String? = nil
    ) -> Trip {
        Trip(
            destination: Destination(name: "Testford", countryCode: "GB", timeZoneId: "Europe/London", centre: centre),
            dates: TripDates(
                start: SampleGuide.date(start),
                end: SampleGuide.date(end),
                arrives: arrives.map(SampleGuide.time),
                leaves: leaves.map(SampleGuide.time)
            ),
            party: Party(adults: 2, children: 0, mobilityNotes: []),
            budget: Budget(currencyCode: "GBP", stayMaxPerNight: 150, dailySpend: .moderate),
            interests: ["coffee", "markets"],
            pace: .unhurried,
            voice: "Short sentences.",
            travel: travel
        )
    }

    // MARK: Places

    static func place(
        _ id: String,
        name: String,
        kind: PlaceKind,
        hours: OpeningHours = Plan.unknownHours,
        at coordinate: Coordinate = centre,
        approximate: Bool = false
    ) -> Place {
        Place(
            id: id,
            name: name,
            kind: kind,
            location: PlaceLocation(coordinate: coordinate, address: nil, approximate: approximate),
            hours: hours,
            priceLevel: nil,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: true,
            images: [],
            facts: [],
            copy: nil
        )
    }

    static func station() -> Place {
        place(stationId, name: "Testford Station", kind: .station)
    }

    /// A cafe about 550 metres north of the centre, so it is a short walk from the station.
    static func cafe() -> Place {
        place(cafeId, name: "Testford Cafe", kind: .cafe, hours: Plan.alwaysOpen,
              at: SampleGuide.coordinate(52.0050, -1.5000))
    }

    static func hotel() -> Place {
        place(hotelId, name: "Testford Hotel", kind: .lodging, at: SampleGuide.coordinate(52.0010, -1.5010))
    }

    /// A lodging place that is not where the traveller stays.
    static func inn() -> Place {
        place(innId, name: "Riverside Inn", kind: .lodging, at: SampleGuide.coordinate(52.0020, -1.4990))
    }

    static func store() -> Place {
        place(storeId, name: "Testford Luggage", kind: .luggage, hours: Plan.hours(daily: "09:00", "17:00"))
    }

    static func museum() -> Place {
        place(museumId, name: "Testford Museum", kind: .museum, hours: Plan.alwaysOpen)
    }

    // MARK: Stops and days

    static func stop(
        _ id: String,
        at time: String,
        minutes: Int = 30,
        place: String?,
        kind: StopKind = .sight,
        title: String = "Stop",
        body: String = "A stop."
    ) -> Stop {
        Stop(
            id: id,
            kind: kind,
            mealSlot: nil,
            placeId: place,
            start: SampleGuide.time(time),
            minutes: minutes,
            flexible: false,
            alternative: nil,
            copy: StopCopy(title: title, body: body, actionLabel: nil),
            legFromPrevious: nil
        )
    }

    static func day(_ date: String, stops: [Stop] = []) -> Day {
        Day(date: SampleGuide.date(date), copy: DayCopy(title: "Day in Testford", summary: "A walk."), stops: stops)
    }

    // MARK: Guides

    static func guide(
        trip: Trip,
        stay: Stay,
        places: [Place],
        days: [Day] = [],
        bookings: [Booking] = [],
        lists: [PlaceList] = [],
        openQuestions: [String]? = nil
    ) -> Guide {
        var byId: [String: Place] = [:]
        for place in places {
            byId[place.id] = place
        }
        return Guide(
            id: "testford-guide",
            version: 1,
            status: .draft,
            trip: trip,
            bookings: bookings,
            stay: stay,
            places: byId,
            days: days,
            lists: lists,
            tasting: [],
            practical: [],
            sources: [],
            hero: nil,
            notes: nil,
            openQuestions: openQuestions
        )
    }

    /// Scenario (a): a day trip by train with no stay. Arrives at 10:00 at the station and leaves from it at 18:00.
    static func dayTripByTrain() -> Guide {
        let travel = TripTravel(mode: .train, arrivalPlaceId: stationId, departurePlaceId: stationId)
        return guide(
            trip: trip(start: "2026-11-22", end: "2026-11-22", travel: travel, arrives: "10:00", leaves: "18:00"),
            stay: noStay,
            places: [station(), cafe()],
            days: [day("2026-11-22", stops: [
                stop("coffee", at: "11:00", minutes: 45, place: cafeId, body: "Coffee and cake."),
                stop("home", at: "17:30", minutes: 20, place: stationId, kind: .travel,
                     body: "Walk back to the station.")
            ])],
            lists: [PlaceList(title: "Eat", caption: "Lunch.", placeIds: [cafeId], key: .eat)]
        )
    }

    /// Scenario (b): an overnight trip with a booked stay, check-in at 15:00 and check-out at 11:00 (estimated).
    static func overnightWithStay() -> Guide {
        let stay = Stay(
            placeId: hotelId,
            checkIn: SampleGuide.time("15:00"),
            checkOut: SampleGuide.time("11:00"),
            luggage: nil,
            arrangement: .booked,
            timesEstimated: true
        )
        return guide(
            trip: trip(start: "2026-11-22", end: "2026-11-24"),
            stay: stay,
            places: [hotel(), cafe()],
            days: [
                day("2026-11-22", stops: [
                    stop("in", at: "15:00", minutes: 20, place: hotelId, kind: .logistics,
                         title: "Check in", body: "Check in at the hotel, then drop your bags.")
                ]),
                day("2026-11-23", stops: [
                    stop("coffee", at: "10:00", minutes: 45, place: cafeId, body: "Coffee and cake.")
                ]),
                day("2026-11-24", stops: [
                    stop("out", at: "10:30", minutes: 20, place: hotelId, kind: .logistics,
                         title: "Check out", body: "Check out of the hotel by 11:00.")
                ])
            ],
            openQuestions: ["Late check-out at the hotel?", "Confirm check-in 15:00 and check-out 11:00."]
        )
    }

    /// Scenario (c): a multi-day trip with no stay named. The stop body and open questions are given by the test.
    static func multiDayWithoutStay(body: String = "Coffee and cake.", openQuestions: [String]? = nil) -> Guide {
        let stay = Stay(placeId: nil, checkIn: nil, checkOut: nil, luggage: nil, arrangement: .unknown)
        return guide(
            trip: trip(start: "2026-11-22", end: "2026-11-24"),
            stay: stay,
            places: [cafe()],
            days: [
                day("2026-11-22", stops: [stop("coffee", at: "10:00", minutes: 45, place: cafeId, body: body)]),
                day("2026-11-23"),
                day("2026-11-24")
            ],
            openQuestions: openQuestions
        )
    }

    /// Scenario (d): a day trip where the traveller named a stay but no times. The stop body is given by the test.
    static func sameDayWithStay(body: String) -> Guide {
        let stay = Stay(placeId: hotelId, checkIn: nil, checkOut: nil, luggage: nil, arrangement: .booked,
                        timesEstimated: nil)
        return guide(
            trip: trip(start: "2026-11-22", end: "2026-11-22"),
            stay: stay,
            places: [hotel(), cafe()],
            days: [day("2026-11-22", stops: [
                stop("rest", at: "16:00", minutes: 60, place: hotelId, kind: .rest, title: "Rest", body: body)
            ])]
        )
    }

    /// A guide made before `arrangement` was recorded: the stay has a place id, and the place is the old unbooked
    /// placeholder (approximate) or a real place. Trip is one day or three.
    static func legacyGuide(oneDay: Bool, approximate: Bool) -> Guide {
        let stay = Stay(placeId: "manual:stay", checkIn: SampleGuide.time("15:00"),
                        checkOut: SampleGuide.time("11:00"), luggage: nil)
        let end = oneDay ? "2026-11-22" : "2026-11-24"
        return guide(
            trip: trip(start: "2026-11-22", end: end),
            stay: stay,
            places: [place("manual:stay", name: "Placeholder Stay", kind: .lodging, approximate: approximate)]
        )
    }

    /// The Leeds-like day trip: no stay, an invented lodging pin in the centre, a rest stop there, and open questions
    /// about accommodation and check-in.
    static func leedsLikeDayTrip() -> Guide {
        guide(
            trip: trip(start: "2026-11-22", end: "2026-11-22"),
            stay: noStay,
            places: [inn(), cafe()],
            days: [day("2026-11-22", stops: [
                stop("rest", at: "15:00", minutes: 30, place: innId, kind: .rest, title: "Rest",
                     body: "Put your feet up.")
            ])],
            openQuestions: ["Do you need accommodation?", "Confirm check-in 15:00 and check-out 11:00."]
        )
    }

    /// A day trip by train with a luggage store: no stay place, but a luggage slot at the store. Arrives at 10:00.
    static func dayTripWithLuggageStore(stops: [Stop]) -> Guide {
        let travel = TripTravel(mode: .train, arrivalPlaceId: stationId, departurePlaceId: nil)
        let stay = Stay(
            placeId: nil,
            checkIn: nil,
            checkOut: nil,
            luggage: LuggageSlot(placeId: storeId, opens: SampleGuide.time("09:00"), closes: SampleGuide.time("17:00")),
            arrangement: .notNeeded
        )
        return guide(
            trip: trip(start: "2026-11-22", end: "2026-11-22", travel: travel, arrives: "10:00"),
            stay: stay,
            places: [station(), store(), cafe()],
            days: [day("2026-11-22", stops: stops)]
        )
    }
}
