import GuideKit

/// Turns Foursquare regular hours into GuideKit opening hours.
///
/// Foursquare day numbers run 1 (Monday) to 7 (Sunday). Times are "HHMM". "2400" means the end of the day, so it is
/// read as "0000". A close earlier than the open is an overnight period, which GuideKit already models.
public enum HoursMapper {
    public struct Result: Sendable, Equatable {
        public let hours: OpeningHours
        /// Entries that could not be read, such as an unknown day number or a malformed time.
        public let skippedEntries: Int
    }

    public static func openingHours(from hours: FoursquareHours?) -> Result {
        guard let hours else {
            return Result(hours: unknownHours, skippedEntries: 0)
        }
        var weekly: [WeeklyPeriod] = []
        var skipped = 0
        for entry in hours.regular {
            guard let weekday = weekday(for: entry.day),
                  let open = time(entry.open),
                  let close = time(entry.close)
            else {
                skipped += 1
                continue
            }
            weekly.append(WeeklyPeriod(weekday: weekday, open: open, close: close))
        }
        let known = !weekly.isEmpty
        let opening = OpeningHours(hoursKnown: known, weekly: weekly, exceptions: [])
        return Result(hours: known ? opening : unknownHours, skippedEntries: skipped)
    }

    static var unknownHours: OpeningHours {
        OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
    }

    static func weekday(for day: Int) -> Weekday? {
        let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        guard (1...7).contains(day) else { return nil }
        return order[day - 1]
    }

    static func time(_ text: String) -> LocalTime? {
        guard text.utf8.count == 4, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let normalised = text == "2400" ? "0000" : text
        guard let hour = Int(normalised.prefix(2)), let minute = Int(normalised.suffix(2)) else { return nil }
        return LocalTime(hour: hour, minute: minute)
    }
}
