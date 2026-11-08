import Foundation
import GuideKit

/// What an OSM `opening_hours` string says. `hours.hoursKnown` is false when any part of the string could not be read.
public struct OpeningHoursReading: Sendable, Equatable {
    public let hours: OpeningHours
    /// Notes about parts that were left out, such as public holiday rules. Read them before trusting the hours.
    public let warnings: [String]
    /// Why the hours are unknown. Nil when they were read.
    public let reason: String?
}

/// Reads OpenStreetMap `opening_hours` strings.
///
/// Supported: day ranges and lists ("Mo-Fr", "Sa,Su", "Fr-Mo" wrapping the week), several time ranges in one rule
/// ("10:00-12:00,14:00-18:00"), "off" and "closed", "24/7", overnight ranges, a close of "00:00" or "24:00", and rule
/// order, where a later rule replaces the earlier one for the days it names. Public holiday ("PH") and school holiday
/// ("SH") selectors are left out with a warning.
///
/// Anything else (month or date ranges, week numbers, sunrise or sunset, comments, interval or open-ended times) makes
/// the whole string unknown, with a reason. Nothing is guessed.
public enum OpeningHoursParser {
    private static let dayCodes = ["mo", "tu", "we", "th", "fr", "sa", "su"]
    private static let holidayCodes = ["PH", "SH"]
    private static let closedWords = ["off", "closed"]
    private static let monthAbbreviations: Set<String> = [
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    ]
    private static let sunTerms: Set<String> = ["sunrise", "sunset", "dawn", "dusk"]

    public static func parse(_ text: String) -> OpeningHoursReading {
        let rules = text.split(separator: ";").map { tidy(String($0)) }.filter { !$0.isEmpty }
        guard !rules.isEmpty else {
            return OpeningHoursReading(hours: unknownHours, warnings: [], reason: "no opening hours given")
        }
        // Day index 0 is Monday. A day's entry is replaced whole by each later rule that names it.
        var table: [Int: [TimePeriod]] = [:]
        var warnings: [String] = []
        var appliedRules = 0
        for rule in rules {
            switch read(rule) {
            case .applied(let effect, let warning):
                appliedRules += 1
                if let warning {
                    warnings.append(warning)
                }
                for day in effect.days {
                    table[day] = effect.periods
                }
            case .holidayOnly(let warning):
                warnings.append(warning)
            case .unsupported(let reason):
                return OpeningHoursReading(hours: unknownHours, warnings: warnings, reason: reason)
            }
        }
        guard appliedRules > 0 else {
            return OpeningHoursReading(
                hours: unknownHours,
                warnings: warnings,
                reason: "only public holiday rules, which are not read"
            )
        }
        var weekly: [WeeklyPeriod] = []
        for day in 0..<7 {
            for period in table[day] ?? [] {
                weekly.append(WeeklyPeriod(weekday: Weekday.allCases[day], open: period.open, close: period.close))
            }
        }
        let hours = OpeningHours(hoursKnown: true, weekly: weekly, exceptions: [])
        return OpeningHoursReading(hours: hours, warnings: warnings, reason: nil)
    }

    private static var unknownHours: OpeningHours {
        OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
    }

    private struct Effect {
        let days: [Int]
        /// Empty when the days are closed.
        let periods: [TimePeriod]
    }

    private enum RuleResult {
        case applied(Effect, warning: String?)
        case holidayOnly(warning: String)
        case unsupported(reason: String)
    }

    private static func read(_ rule: String) -> RuleResult {
        if rule == "24/7" {
            let allDay = TimePeriod(open: midnight, close: midnight)
            return .applied(Effect(days: Array(0..<7), periods: [allDay]), warning: nil)
        }
        if let reason = unsupportedReason(rule) {
            return .unsupported(reason: reason)
        }
        guard let parts = splitRule(rule) else {
            return .unsupported(reason: "could not read the rule \"\(rule)\"")
        }
        guard let periods = periods(forValue: parts.value) else {
            return .unsupported(reason: "could not read the times in \"\(rule)\"")
        }
        guard let selector = parts.selector else {
            return .applied(Effect(days: Array(0..<7), periods: periods), warning: nil)
        }
        return applySelector(selector, periods: periods, rule: rule)
    }

    /// A rule's day selector and value. The selector is absent when the rule is only times, which means every day.
    private static func splitRule(_ rule: String) -> (selector: String?, value: String)? {
        let parts = rule.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        if parts.count == 1, parts[0].first?.isNumber == true {
            return (nil, parts[0])
        }
        return nil
    }

    /// The periods for a rule's value. "off" and "closed" give none. Nil when the times cannot be read.
    private static func periods(forValue value: String) -> [TimePeriod]? {
        if closedWords.contains(value.lowercased()) {
            return []
        }
        return timePeriods(value)
    }

    /// Applies the days a selector names. Holiday items are left out. A selector that names no days is unreadable,
    /// unless it only names holidays.
    private static func applySelector(_ selector: String, periods: [TimePeriod], rule: String) -> RuleResult {
        let unreadable = RuleResult.unsupported(reason: "could not read the days in \"\(rule)\"")
        var days = Set<Int>()
        var sawHoliday = false
        for item in selector.split(separator: ",").map(String.init) {
            if holidayCodes.contains(item.uppercased()) {
                sawHoliday = true
                continue
            }
            guard let range = dayRange(item) else {
                return unreadable
            }
            days.formUnion(range)
        }
        if days.isEmpty {
            guard sawHoliday else { return unreadable }
            return .holidayOnly(warning: "Holiday rule left out: \"\(rule)\".")
        }
        let warning = sawHoliday ? "Holiday part of \"\(rule)\" left out." : nil
        return .applied(Effect(days: days.sorted(), periods: periods), warning: warning)
    }

    /// The reason a rule is outside what this parser reads, or nil when it may be read.
    private static func unsupportedReason(_ rule: String) -> String? {
        let lower = rule.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains(where: { monthAbbreviations.contains($0) }) || words.contains("easter") {
            return "month or date ranges are not supported: \"\(rule)\""
        }
        if lower.contains("week") {
            return "week numbers are not supported: \"\(rule)\""
        }
        if words.contains(where: { sunTerms.contains($0) }) {
            return "sunrise and sunset times are not supported: \"\(rule)\""
        }
        if rule.contains("\"") {
            return "comments are not supported: \"\(rule)\""
        }
        return nil
    }

    /// The days a single selector item names: "Mo", or a range such as "Mo-Fr" or "Fr-Mo", which wraps the week.
    private static func dayRange(_ item: String) -> Set<Int>? {
        let ends = item.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if ends.count == 1 {
            guard let day = dayIndex(ends[0]) else { return nil }
            return [day]
        }
        guard ends.count == 2, let first = dayIndex(ends[0]), let last = dayIndex(ends[1]) else {
            return nil
        }
        var result = Set<Int>()
        var day = first
        while true {
            result.insert(day)
            if day == last {
                break
            }
            day = (day + 1) % 7
        }
        return result
    }

    private static func dayIndex(_ code: String) -> Int? {
        dayCodes.firstIndex(of: code.lowercased())
    }

    /// The open periods in one rule's value, such as "10:00-12:00,14:00-18:00". Nil when any span cannot be read.
    private static func timePeriods(_ text: String) -> [TimePeriod]? {
        var periods: [TimePeriod] = []
        for span in text.split(separator: ",", omittingEmptySubsequences: false) {
            let ends = span.split(separator: "-", omittingEmptySubsequences: false)
            guard ends.count == 2,
                  let openMinutes = clock(ends[0], maxHour: 23),
                  let closeMinutes = clock(ends[1], maxHour: 27),
                  let period = period(openMinutes: openMinutes, closeMinutes: closeMinutes)
            else {
                return nil
            }
            periods.append(period)
        }
        return periods
    }

    /// Minutes since midnight for "HH:MM", with hours up to `maxHour`. Two digits each, so "9:00" is refused.
    private static func clock(_ text: Substring, maxHour: Int) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2 else { return nil }
        let digits = parts.allSatisfy { part in part.allSatisfy { $0.isASCII && $0.isNumber } }
        guard digits, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...maxHour).contains(hour), (0...59).contains(minute)
        else {
            return nil
        }
        return hour * 60 + minute
    }

    /// A close past midnight is written as 24:00 or later. It is brought back into the day, which makes the period
    /// close after midnight (or, when it is equal to the open time, 24 hours), as GuideKit models it.
    private static func period(openMinutes: Int, closeMinutes: Int) -> TimePeriod? {
        let close = closeMinutes >= 1440 ? closeMinutes - 1440 : closeMinutes
        guard let open = LocalTime(minutesSinceMidnight: openMinutes),
              let closing = LocalTime(minutesSinceMidnight: close)
        else {
            return nil
        }
        return TimePeriod(open: open, close: closing)
    }

    private static var midnight: LocalTime {
        guard let zero = LocalTime(minutesSinceMidnight: 0) else {
            preconditionFailure("00:00 is always a valid time")
        }
        return zero
    }

    /// Removes spaces next to "," and "-", and collapses the rest to one space, so "Mo - Fr 10:00 , 12:00-14:00" reads
    /// like "Mo-Fr 10:00,12:00-14:00".
    static func tidy(_ text: String) -> String {
        var cleaned = ""
        var pendingSpace = false
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character == " " || character == "\t" {
                pendingSpace = true
                continue
            }
            if pendingSpace, let last = cleaned.last, !",-".contains(last), !",-".contains(character) {
                cleaned.append(" ")
            }
            pendingSpace = false
            cleaned.append(character)
        }
        return cleaned
    }
}
