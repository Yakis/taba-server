import Foundation
import GuideKit

/// Hand-built guides with made-up places, small enough to count by hand. Every place sits at the same spot, so each
/// walk between two stops takes the 1-minute minimum.
enum TestGuides {
    static let arrival = date("2026-11-22")
    static let middle = date("2026-11-23")
    static let departure = date("2026-11-24")

    /// The main test guide: three days, a full day in the middle. The interests default to Food, Pubs, Art and Music,
    /// and nothing serves Music. With `recorded`, the places say which interests they serve, and the market does not
    /// serve Food.
    static func tour(interests: [String] = ["Food", "Pubs", "Art", "Music"], recorded: Bool = false) -> Guide {
        let places = [
            place("p-market", .market, level: 1, recorded: recorded ? ["Markets"] : nil),
            place("p-cafe", .cafe, level: 1, recorded: recorded ? ["Food"] : nil),
            place("p-gallery", .museum, level: nil, hoursKnown: false, recorded: recorded ? ["Art"] : nil),
            place("p-pub", .pub, level: 4, recorded: recorded ? ["Pubs"] : nil),
            place("p-unused", .other, level: nil)
        ]
        let days = [
            day(arrival, [
                stop("d1-s1", .sight, "p-market", "14:00", 30, body: "The famous old stone market is busy.")
            ]),
            day(middle, [
                stop("d2-s1", .sight, "p-gallery", "09:30", 60, body: quietWords(61)),
                stop("d2-s2", .sight, "p-market", "11:00", 45, body: "Walk round the famous old stone square."),
                stop("d2-s3", .meal, "p-cafe", "12:00", 60, meal: .lunch),
                stop("d2-s4", .drink, "p-pub", "18:00", 60)
            ]),
            day(departure, [
                stop("d3-s1", .sight, "p-market", "10:00", 10, body: "Look at the famous old stone arches.")
            ])
        ]
        return guide(places: places, days: days, interests: interests)
    }

    /// A second guide with other places, so that no place is shared with `tour()`.
    static func other() -> Guide {
        let places = [place("q-market", .market, level: 2), place("q-square", .landmark, level: nil)]
        let days = [
            day(arrival, [
                stop("e1-s1", .sight, "q-market", "10:00", 40),
                stop("e1-s2", .sight, "q-square", "11:30", 30)
            ])
        ]
        return guide(places: places, days: days, interests: ["Markets"], lists: [], tasting: [], practical: [],
                     sources: [])
    }

    /// Builds a guide from parts: a three-day trip with no stay, and the test notes, tasting, facts and sources.
    static func guide(
        places: [Place], days: [Day], interests: [String], pace: Pace = .unhurried, spend: DailySpend = .moderate,
        lists: [PlaceList]? = nil, tasting: [TasteItem]? = nil, practical: [Fact]? = nil, sources: [Source]? = nil,
        notes: GuideNotes? = GuideNotes(weather: "Rain likely.", light: "", backupPlan: "Museums.", rules: "")
    ) -> Guide {
        Guide(
            id: "test-guide",
            version: 1,
            status: .ready,
            trip: Trip(
                destination: Destination(name: "Testville", countryCode: "GB", timeZoneId: "Europe/London",
                                         centre: coordinate()),
                dates: TripDates(start: arrival, end: departure),
                party: Party(adults: 1, children: 0, mobilityNotes: []),
                budget: Budget(currencyCode: "GBP", stayMaxPerNight: 100, dailySpend: spend),
                interests: interests,
                pace: pace,
                voice: "Plain and warm."
            ),
            bookings: [],
            stay: Stay(placeId: nil, checkIn: nil, checkOut: nil, luggage: nil, arrangement: .unknown),
            places: Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) }),
            days: days,
            lists: lists ?? [
                PlaceList(title: "Eat", caption: "", placeIds: ["p-cafe", "p-missing"], key: .eat),
                PlaceList(title: "Drink", caption: "", placeIds: ["p-market"], key: .drink)
            ],
            tasting: tasting ?? [
                TasteItem(name: "Bread", note: "Ask for it warm."),
                TasteItem(name: "Arbroath smokies", note: "Smoked fish, by the harbour.")
            ],
            practical: practical ?? [
                Fact(text: "Open late on Fridays.", sourceId: "src-1", checkedAt: arrival),
                Fact(text: "Card only.", sourceId: "src-missing", checkedAt: arrival)
            ],
            sources: sources ?? [Source(id: "src-1", url: "https://example.com/", title: "Example",
                                        checkedAt: arrival)],
            hero: nil,
            notes: notes,
            openQuestions: ["Check the gallery hours."]
        )
    }

    static func place(
        _ id: String, _ kind: PlaceKind, level: Int?, hoursKnown: Bool = true, recorded: [String]? = nil
    ) -> Place {
        let weekly = Weekday.allCases.map {
            WeeklyPeriod(weekday: $0, open: time("08:00"), close: time("22:00"))
        }
        let hours = OpeningHours(hoursKnown: hoursKnown, weekly: hoursKnown ? weekly : [], exceptions: [])
        return Place(
            id: id, name: id, kind: kind,
            location: PlaceLocation(coordinate: coordinate(), address: nil, approximate: false),
            hours: hours, priceLevel: level, booking: PlaceBooking(needed: false, url: nil), indoor: true,
            images: [], facts: [], copy: nil, interests: recorded
        )
    }

    static func stop(
        _ id: String, _ kind: StopKind, _ placeId: String, _ start: String, _ minutes: Int,
        meal: MealSlot? = nil, body: String = "A short stop."
    ) -> Stop {
        Stop(id: id, kind: kind, mealSlot: meal, placeId: placeId, start: time(start), minutes: minutes,
             flexible: false, alternative: nil, copy: StopCopy(title: id, body: body, actionLabel: nil),
             legFromPrevious: nil)
    }

    static func day(_ date: LocalDate, _ stops: [Stop]) -> Day {
        Day(date: date, copy: DayCopy(title: "A day", summary: "Some things to see."), stops: stops)
    }

    static func date(_ text: String) -> LocalDate {
        guard let value = LocalDate(text) else { preconditionFailure("Bad test date \(text)") }
        return value
    }

    static func time(_ text: String) -> LocalTime {
        guard let value = LocalTime(text) else { preconditionFailure("Bad test time \(text)") }
        return value
    }

    static func coordinate() -> Coordinate {
        guard let value = Coordinate(latitude: 53.8, longitude: -1.5) else { preconditionFailure("Bad coordinate") }
        return value
    }

    /// A body of `count` copies of one word: long, but it repeats no three-word phrase in any other stop.
    private static func quietWords(_ count: Int) -> String {
        Array(repeating: "quiet", count: count).joined(separator: " ")
    }
}
