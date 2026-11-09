/// Times, dates, prices and short phrases as the HTML guide shows them. Names are fixed in English and every format is
/// written out here, so the output never depends on the device's language or locale.
enum RenderText {
    /// "Jan" to "Dec".
    static let shortMonths = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]
    /// "January" to "December".
    static let longMonths = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    /// "09:05", 24-hour and zero padded.
    static func time(_ time: LocalTime) -> String {
        time.description
    }

    /// A short duration: "50 min", "1 h", "1 h 30 min". Negative values read as zero.
    static func duration(minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let rest = total % 60
        if hours == 0 {
            return "\(rest) min"
        }
        if rest == 0 {
            return "\(hours) h"
        }
        return "\(hours) h \(rest) min"
    }

    /// "Mon", "Tue" and so on.
    static func shortWeekday(_ weekday: Weekday) -> String {
        String(longWeekday(weekday).prefix(3))
    }

    /// "Monday" to "Sunday".
    static func longWeekday(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    /// "Sun 23 Nov", for the hours lists.
    static func shortDay(_ date: LocalDate) -> String {
        "\(shortWeekday(date.weekday)) \(date.day) \(shortMonths[date.month - 1])"
    }

    /// "Monday 24 Nov", for the day's eyebrow.
    static func dayTitleDate(_ date: LocalDate) -> String {
        "\(longWeekday(date.weekday)) \(date.day) \(shortMonths[date.month - 1])"
    }

    /// "4 Nov 2025", for the sources' check dates.
    static func shortDate(_ date: LocalDate) -> String {
        "\(date.day) \(shortMonths[date.month - 1]) \(date.year)"
    }

    /// "23–25 Nov 2025", "30 Nov – 2 Dec 2025" or "23 Nov 2025" for a single day.
    static func tripDates(_ dates: TripDates) -> String {
        let start = dates.start
        let end = dates.end
        if start == end {
            return shortDate(start)
        }
        if start.year == end.year, start.month == end.month {
            return "\(start.day)–\(end.day) \(shortMonths[end.month - 1]) \(end.year)"
        }
        if start.year == end.year {
            return "\(start.day) \(shortMonths[start.month - 1]) – \(end.day) \(shortMonths[end.month - 1]) \(end.year)"
        }
        return "\(shortDate(start)) – \(shortDate(end))"
    }

    /// The currency symbol repeated for the price level ("££"), clamped to 1...4. Nil when the level is unknown.
    static func price(level: Int?, currencyCode: String) -> String? {
        guard let level else { return nil }
        let symbol = switch currencyCode.uppercased() {
        case "GBP": "£"
        case "EUR": "€"
        case "JPY": "¥"
        default: "$"
        }
        return String(repeating: symbol, count: min(max(level, 1), 4))
    }

    /// "Rain likely, 8°", from the summary and the high. Nil when there is no outlook.
    static func weatherLine(_ outlook: DayOutlook?) -> String? {
        guard let outlook else { return nil }
        guard let high = outlook.highCelsius else { return HTML.nonBlank(outlook.summary) }
        let summary = HTML.trimmed(outlook.summary)
        return summary.isEmpty ? "\(high)°" : "\(summary), \(high)°"
    }

    /// "Sunrise 08:07 · Sunset 15:51" at the destination on `date`. Nil when neither time is known.
    static func sunLine(on date: LocalDate, guide: Guide) -> String? {
        let destination = guide.trip.destination
        guard let sun = SunTimes.compute(
            date: date,
            at: destination.centre,
            timeZoneId: destination.timeZoneId
        ) else {
            return nil
        }
        let parts = [
            sun.sunrise.map { "Sunrise \(time($0))" },
            sun.sunset.map { "Sunset \(time($0))" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The name of a kind of place, for people: "Cafe", "Luggage store".
    static func placeKindLabel(_ kind: PlaceKind) -> String { // swiftlint:disable:this cyclomatic_complexity
        switch kind {
        case .market: "Market"
        case .foodHall: "Food hall"
        case .cafe: "Cafe"
        case .restaurant: "Restaurant"
        case .pub: "Pub"
        case .bar: "Bar"
        case .venue: "Music venue"
        case .viewpoint: "Viewpoint"
        case .street: "Street"
        case .neighbourhood: "Neighbourhood"
        case .landmark: "Landmark"
        case .museum: "Museum"
        case .shop: "Shop"
        case .grocery: "Groceries"
        case .station: "Station"
        case .lodging: "Stay"
        case .luggage: "Luggage store"
        case .other: "Place"
        }
    }
}
