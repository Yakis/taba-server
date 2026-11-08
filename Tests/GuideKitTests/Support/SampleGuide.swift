import GuideKit

/// A small hand-built guide for model tests. It describes made-up places, not a real trip.
enum SampleGuide {
    static let cafeId = "manual:sample-cafe"
    static let marketId = "osm:sample-market"
    static let hotelId = "manual:sample-hotel"
    static let placeIds = [cafeId, marketId, hotelId]

    static func make(
        trip: Trip = SampleGuide.trip(),
        bookings: [Booking] = [SampleGuide.trainBooking()],
        days: [Day] = [SampleGuide.day()],
        places: [String: Place] = SampleGuide.samplePlaces()
    ) -> Guide {
        Guide(
            id: "sample-guide",
            version: 1,
            status: .draft,
            trip: trip,
            bookings: bookings,
            stay: Stay(
                placeId: hotelId,
                checkIn: time("15:00"),
                checkOut: time("10:00"),
                luggage: LuggageSlot(placeId: hotelId, opens: time("08:00"), closes: time("20:00"))
            ),
            places: places,
            days: days,
            lists: [PlaceList(title: "Coffee", caption: "For a slow morning.", placeIds: [cafeId])],
            tasting: [TasteItem(name: "Sample bake", note: "Ask for it warm.")],
            practical: [Fact(text: "Card payments only.", sourceId: "sample-source", checkedAt: date("2026-11-08"))],
            sources: [
                Source(
                    id: "sample-source",
                    url: "https://example.com/sample",
                    title: "Sample page",
                    checkedAt: date("2026-11-08")
                )
            ]
        )
    }

    static func trip(start: String = "2026-11-22", end: String = "2026-11-24") -> Trip {
        Trip(
            destination: Destination(
                name: "Sampleburgh",
                countryCode: "GB",
                timeZoneId: "Europe/London",
                centre: coordinate(55.9533, -3.1883)
            ),
            dates: TripDates(start: date(start), end: date(end)),
            party: Party(adults: 2, children: 0, mobilityNotes: ["stairs fine"]),
            budget: Budget(currencyCode: "GBP", stayMaxPerNight: 150, dailySpend: .moderate),
            interests: ["coffee", "markets"],
            pace: .unhurried,
            voice: "Short sentences. Dry humour."
        )
    }

    static func samplePlaces() -> [String: Place] {
        [cafeId: cafe(), marketId: market(), hotelId: hotel()]
    }

    static func cafe(closesAt: String = "17:00") -> Place {
        Place(
            id: cafeId,
            name: "Sample Cafe",
            kind: .cafe,
            location: PlaceLocation(
                coordinate: coordinate(55.9521, -3.1880),
                address: "1 Example Street",
                approximate: false
            ),
            hours: OpeningHours(
                hoursKnown: true,
                weekly: [WeeklyPeriod(weekday: .monday, open: time("08:00"), close: time(closesAt))],
                exceptions: [DateException(date: date("2026-11-23"), closed: true, periods: [])]
            ),
            priceLevel: 2,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: true,
            images: [ImageRef(url: "https://example.com/cafe.jpg", credit: "Example Photographer")],
            facts: [Fact(text: "Closed on public holidays.", sourceId: "sample-source", checkedAt: date("2026-11-08"))],
            copy: PlaceCopy(tag: "Coffee", blurb: "A quiet room near the market.")
        )
    }

    static func market() -> Place {
        Place(
            id: marketId,
            name: "Sample Market",
            kind: .market,
            location: PlaceLocation(coordinate: coordinate(55.9490, -3.1950), address: nil, approximate: true),
            hours: OpeningHours(
                hoursKnown: true,
                weekly: [WeeklyPeriod(weekday: .sunday, open: time("09:00"), close: time("17:00"))],
                exceptions: []
            ),
            priceLevel: nil,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: false,
            images: [],
            facts: [],
            copy: nil
        )
    }

    static func hotel(priceLevel: Int? = 3) -> Place {
        Place(
            id: hotelId,
            name: "Sample Hotel",
            kind: .lodging,
            location: PlaceLocation(
                coordinate: coordinate(55.9500, -3.1900),
                address: "2 Example Road",
                approximate: false
            ),
            hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: []),
            priceLevel: priceLevel,
            booking: PlaceBooking(needed: true, url: "https://example.com/book"),
            indoor: true,
            images: [],
            facts: [],
            copy: PlaceCopy(tag: "Base", blurb: "Our room for the trip.")
        )
    }

    static func trainBooking(
        departs: String = "2026-11-22T08:10",
        arrives: String = "2026-11-22T12:30"
    ) -> Booking {
        Booking(
            id: "booking-train-out",
            kind: .train,
            from: "Sample Station",
            to: "Sampleburgh Central",
            departs: dateTime(departs),
            arrives: dateTime(arrives),
            notes: "Check the platform on the day."
        )
    }

    static func day(stops: [Stop] = SampleGuide.stops()) -> Day {
        Day(
            date: date("2026-11-22"),
            copy: DayCopy(title: "Arrival", summary: "Settle in and eat well."),
            stops: stops
        )
    }

    static func sightStop(id: String, minutes: Int) -> Stop {
        Stop(
            id: id,
            kind: .sight,
            mealSlot: nil,
            placeId: marketId,
            start: time("15:00"),
            minutes: minutes,
            flexible: false,
            alternative: nil,
            copy: StopCopy(title: "Sight", body: "A sight.", actionLabel: nil),
            legFromPrevious: nil
        )
    }

    static func stops() -> [Stop] {
        [
            Stop(
                id: "d1-lunch",
                kind: .meal,
                mealSlot: .lunch,
                placeId: cafeId,
                start: time("13:15"),
                minutes: 60,
                flexible: true,
                alternative: StopAlternative(placeId: marketId, reason: .rain),
                copy: StopCopy(title: "Lunch", body: "A short walk, then soup.", actionLabel: "Open"),
                legFromPrevious: Leg(mode: .walk, minutes: 12, metres: 900)
            ),
            Stop(
                id: "d1-market",
                kind: .sight,
                mealSlot: nil,
                placeId: marketId,
                start: time("15:00"),
                minutes: 45,
                flexible: false,
                alternative: nil,
                copy: StopCopy(title: "Market walk", body: "Look at the stalls.", actionLabel: nil),
                legFromPrevious: nil
            ),
            Stop(
                id: "d1-transfer",
                kind: .travel,
                mealSlot: nil,
                placeId: nil,
                start: time("16:00"),
                minutes: 20,
                flexible: true,
                alternative: nil,
                copy: StopCopy(title: "Back to base", body: "Take the bus.", actionLabel: nil),
                legFromPrevious: nil
            )
        ]
    }

    static func planDraft() -> PlanDraft {
        PlanDraft(
            days: [
                PlanDraftDay(
                    date: date("2026-11-22"),
                    copy: DayCopy(title: "Arrival", summary: "Settle in."),
                    stops: [
                        PlanDraftStop(
                            placeId: cafeId,
                            kind: .meal,
                            mealSlot: .lunch,
                            start: time("13:15"),
                            minutes: 60,
                            flexible: true,
                            alternative: StopAlternative(placeId: marketId, reason: .closed),
                            copy: StopCopy(title: "Lunch", body: "Soup and bread.", actionLabel: nil)
                        ),
                        PlanDraftStop(
                            placeId: nil,
                            kind: .rest,
                            mealSlot: nil,
                            start: time("17:00"),
                            minutes: 30,
                            flexible: true,
                            alternative: nil,
                            copy: StopCopy(title: "Rest", body: "Put your feet up.", actionLabel: nil)
                        )
                    ]
                )
            ],
            lists: [PlaceList(title: "Coffee", caption: "For a slow morning.", placeIds: [cafeId])],
            tasting: [TasteItem(name: "Sample bake", note: "Ask for it warm.")],
            notes: "Draft for testing only."
        )
    }

    // MARK: - Fixture helpers. These trap on bad input, which is fine because the inputs are literals.

    static func date(_ text: String) -> LocalDate {
        guard let value = LocalDate(text) else { preconditionFailure("Bad fixture date \(text)") }
        return value
    }

    static func time(_ text: String) -> LocalTime {
        guard let value = LocalTime(text) else { preconditionFailure("Bad fixture time \(text)") }
        return value
    }

    static func dateTime(_ text: String) -> LocalDateTime {
        guard let value = LocalDateTime(text) else { preconditionFailure("Bad fixture date-time \(text)") }
        return value
    }

    static func coordinate(_ latitude: Double, _ longitude: Double) -> Coordinate {
        guard let value = Coordinate(latitude: latitude, longitude: longitude) else {
            preconditionFailure("Bad fixture coordinate \(latitude), \(longitude)")
        }
        return value
    }
}
