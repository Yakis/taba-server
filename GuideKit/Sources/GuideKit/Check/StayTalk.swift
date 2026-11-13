import Foundation

/// Finds words that talk about somewhere to sleep, or about checking in and out of it. The guide's facts decide
/// whether such words may appear (see `Guide.contradictions`), so prose can never invent a stay.
///
/// "Check out the market" is not a check-out, and "your stay in Leeds" means the visit, so neither is matched. Place
/// names are removed before matching, so a bar called "The Queens Hotel" is not talk about a hotel.
public enum StayTalk {
    private static let accommodationPattern = #"(?<![\p{L}\p{N}])(?:accommodation|hotels?|hostels?|guest\s?houses?|"#
        + #"b\s?&\s?bs?|bed\s+and\s+breakfasts?|airbnbs?|lodgings?|motels?|the\s+stay|your\s+room|"#
        + #"where\s+you(?:'re|’re|\s+are)\s+staying|stay\s+overnight|overnight\s+stay)(?![\p{L}\p{N}])"#
    /// Checking in for a flight or online is not a stay: "check in for your flight", "online check-in".
    private static let checkPattern = #"(?<!online\s)(?<!flight\s)(?<![\p{L}\p{N}])"#
        + #"(?:check[\s\p{Pd}]?ins?(?!\s+(?:for|online|desks?|counters?|closes))|checking[\s\p{Pd}]in(?!\s+for)|"#
        + #"check[\p{Pd}]outs?|checkouts?|checking[\s\p{Pd}]out(?=\s+(?:of|from|by|at))|"#
        + #"check\s+out(?=\s+(?:of|from|by|at|time))|check\s+in(?=\s+(?:at|to|from|by|time)))(?![\p{L}\p{N}])"#

    /// The first words about somewhere to sleep in `text`, or nil.
    /// - Parameter names: Place names to ignore, such as the names of the guide's places.
    public static func accommodation(in text: String, ignoring names: [String] = []) -> String? {
        firstMatch(accommodationPattern, in: removing(names, from: text))
    }

    /// The first words about checking in or out in `text`, or nil.
    /// - Parameter names: Place names to ignore.
    public static func checkInOrOut(in text: String, ignoring names: [String] = []) -> String? {
        firstMatch(checkPattern, in: removing(names, from: text))
    }

    private static func removing(_ names: [String], from text: String) -> String {
        names.filter { !$0.isEmpty }.sorted { $0.count > $1.count }.reduce(text) { result, name in
            result.replacingOccurrences(of: name, with: " ", options: [.caseInsensitive])
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(text[range])
    }
}
