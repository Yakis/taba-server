import Foundation
import GuideKit
import ResponsesKit

/// A fixed test trip: a name, a note, how many days from today it starts, and the body the server takes. The body
/// keeps its own `from` and `to` in the file; `requestBody` moves them to the start date the runner picks.
public struct Scenario: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let startInDays: Int
    /// A `TripBuildInput` body, kept as plain JSON so the scorer does not depend on the server.
    public let input: JSONValue

    public enum ScenarioError: Error, Equatable, CustomStringConvertible {
        case badName(String)
        case badDates(String)

        public var description: String {
            switch self {
            case .badName(let name): "Scenario name \"\(name)\" must be letters, digits and hyphens."
            case .badDates(let name): "Scenario \"\(name)\" needs \"from\" and \"to\" dates, in order."
            }
        }
    }

    /// The body for a trip starting `startInDays` after `today`, with the same number of days as the file's trip.
    public func requestBody(today: LocalDate) throws -> Data {
        guard case .object(var fields) = input,
              case .string(let fromText)? = fields["from"], case .string(let toText)? = fields["to"],
              let from = LocalDate(fromText), let to = LocalDate(toText), from <= to,
              let start = today.adding(days: startInDays),
              let end = start.adding(days: Self.dayCount(from: from, to: to)) else {
            throw ScenarioError.badDates(name)
        }
        fields["from"] = .string(start.description)
        fields["to"] = .string(end.description)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONValue.object(fields))
    }

    /// Every `*.json` scenario in the folder, in file name order.
    public static func load(from folder: URL) throws -> [Scenario] {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { file in
            let scenario = try JSONDecoder().decode(Scenario.self, from: Data(contentsOf: file))
            guard scenario.name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !scenario.name.isEmpty else {
                throw ScenarioError.badName(scenario.name)
            }
            return scenario
        }
    }

    /// The number of days after `from` that `to` falls on.
    static func dayCount(from: LocalDate, to: LocalDate) -> Int {
        var count = 0
        var day = from
        while day < to, let next = day.adding(days: 1) {
            day = next
            count += 1
        }
        return count
    }
}

/// Today's date in the UK, where the scenarios' trips are. The runner uses it to date the trips.
public func londonToday(now: Date = Date()) -> LocalDate? {
    var calendar = Calendar(identifier: .gregorian)
    guard let zone = TimeZone(identifier: "Europe/London") else { return nil }
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.year, .month, .day], from: now)
    guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
    return LocalDate(year: year, month: month, day: day)
}
