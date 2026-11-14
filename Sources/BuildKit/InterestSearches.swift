import Foundation

/// Extra OpenStreetMap searches for the traveller's interests, so a place they asked for can become a candidate.
///
/// Each interest is split into words, trimmed and lowercased. An interest matches a row when one of its words is one
/// of the row's words, so "art" does not match "architecture". Labels come out in interest order, each label only
/// once, and at most `maximumSearches` of them. Anything else adds nothing. A label names the OpenStreetMap filters
/// and phrases in `OSMSearches`.
public enum InterestSearches {
    public static let maximumSearches = 4

    private typealias Row = (words: Set<String>, label: String)

    private static let rows: [Row] = [
        (["music", "gig", "gigs", "concert", "concerts"], "music"),
        (["art", "gallery", "galleries"], "galleries"),
        (["nature", "park", "parks", "garden", "gardens"], "parks"),
        (["history", "architecture", "heritage"], "heritage"),
        // Photo spots: scenic lookouts, bridges, plazas and historic sites.
        (["photography", "photo", "photos", "views", "view", "viewpoint", "viewpoints"], "views")
    ]

    /// The extra search labels for `interests`, in interest order, de-duplicated and capped.
    public static func labels(for interests: [String]) -> [String] {
        var result: [String] = []
        for interest in interests {
            for row in matchingRows(for: interest) where !result.contains(row.label) {
                guard result.count < maximumSearches else { return result }
                result.append(row.label)
            }
        }
        return result
    }

    /// The rows that share a word with the interest, in table order.
    private static func matchingRows(for interest: String) -> [Row] {
        let words = Set(
            interest.lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
        )
        return rows.filter { !$0.words.isDisjoint(with: words) }
    }
}
