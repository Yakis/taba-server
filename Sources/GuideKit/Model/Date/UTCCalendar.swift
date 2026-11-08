import Foundation

/// A Gregorian calendar fixed to UTC, so date maths never depends on the device's locale or time zone.
enum UTCCalendar {
    static func make() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }
}
