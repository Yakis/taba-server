import GuideKit

/// Fixed walking minutes, so a test can set gaps against a known walk.
struct FixedWalk: WalkTimes {
    let fixedMinutes: Int

    func minutes(from origin: Coordinate, to destination: Coordinate) -> Int {
        fixedMinutes
    }
}

/// Builders for plan-check tests. Every place is in Edinburgh unless a test says otherwise.
enum Plan {
    static let centre = SampleGuide.coordinate(55.9533, -3.1883)
    static let unknownHours = OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
    static let alwaysOpen = hours(daily: "00:00", "00:00")

    static func hours(daily open: String, _ close: String) -> OpeningHours {
        OpeningHours(
            hoursKnown: true,
            weekly: Weekday.allCases.map {
                WeeklyPeriod(weekday: $0, open: SampleGuide.time(open), close: SampleGuide.time(close))
            },
            exceptions: []
        )
    }

    static func hours(_ periods: [WeeklyPeriod], exceptions: [DateException] = []) -> OpeningHours {
        OpeningHours(hoursKnown: true, weekly: periods, exceptions: exceptions)
    }

    static func place(
        _ id: String,
        name: String = "Test Place",
        kind: PlaceKind = .cafe,
        indoor: Bool = true,
        hours: OpeningHours = unknownHours,
        at coordinate: Coordinate = centre
    ) -> Place {
        Place(
            id: id,
            name: name,
            kind: kind,
            location: PlaceLocation(coordinate: coordinate, address: nil, approximate: false),
            hours: hours,
            priceLevel: nil,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: indoor,
            images: [],
            facts: [],
            copy: nil
        )
    }

    /// A stop starting `start` minutes after midnight.
    static func stop(
        _ id: String,
        start: Int,
        minutes: Int,
        place: String?,
        kind: StopKind = .sight,
        meal: MealSlot? = nil,
        flexible: Bool = false,
        alternative: StopAlternative? = nil
    ) -> Stop {
        Stop(
            id: id,
            kind: kind,
            mealSlot: meal,
            placeId: place,
            start: clock(start),
            minutes: minutes,
            flexible: flexible,
            alternative: alternative,
            copy: StopCopy(title: id, body: "Test stop.", actionLabel: nil),
            legFromPrevious: nil
        )
    }

    static func clock(_ minutes: Int) -> LocalTime {
        guard let value = LocalTime(minutesSinceMidnight: minutes) else {
            preconditionFailure("Bad fixture minutes \(minutes)")
        }
        return value
    }

    static func guide(
        days: [Day],
        places: [Place],
        bookings: [Booking] = [],
        stay: Stay = SampleGuide.stay(),
        trip: Trip = SampleGuide.trip()
    ) -> Guide {
        var dictionary: [String: Place] = [:]
        for place in places {
            dictionary[place.id] = place
        }
        return SampleGuide.make(trip: trip, bookings: bookings, stay: stay, days: days, places: dictionary)
    }

    static func trip(
        start: String,
        end: String,
        pace: Pace = .unhurried,
        centre: Coordinate = centre,
        timeZoneId: String = "Europe/London"
    ) -> Trip {
        Trip(
            destination: Destination(name: "Testville", countryCode: "GB", timeZoneId: timeZoneId, centre: centre),
            dates: TripDates(start: SampleGuide.date(start), end: SampleGuide.date(end)),
            party: Party(adults: 2, children: 0, mobilityNotes: []),
            budget: Budget(currencyCode: "GBP", stayMaxPerNight: 150, dailySpend: .moderate),
            interests: ["food"],
            pace: pace,
            voice: "Plain."
        )
    }

    /// Minutes after midnight of sunset in the test centre, from the same SunTimes API the checker uses.
    static func sunsetMinutes(on date: String, timeZoneId: String = "Europe/London") -> Int {
        guard
            let sun = SunTimes.compute(date: SampleGuide.date(date), at: centre, timeZoneId: timeZoneId),
            let sunset = sun.sunset
        else {
            preconditionFailure("No sunset for \(date)")
        }
        return sunset.minutesSinceMidnight
    }

    static func issues(_ guide: Guide, walk: any WalkTimes = StraightLineWalkTimes()) -> [PlanIssue] {
        PlanChecker(walkTimes: walk).check(guide)
    }

    static func has(_ issues: [PlanIssue], _ kind: IssueKind) -> Bool {
        issues.contains(where: { $0.kind == kind })
    }
}
