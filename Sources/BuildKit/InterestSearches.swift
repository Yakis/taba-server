import Foundation
import SourcesKit

/// Extra Foursquare searches for the traveller's interests, so a place they asked for can become a candidate.
///
/// Each interest is split into words, trimmed and lowercased. An interest matches a row when one of its words is one
/// of the row's words, so "art" does not match "architecture". Searches come out in interest order, each label only
/// once, and at most `maximumSearches` of them. Anything else adds nothing.
public enum InterestSearches {
    public static let maximumSearches = 4

    private typealias Row = (words: Set<String>, search: FoursquarePlacesSource.CategorySearch)

    private static let rows: [Row] = [
        (["music", "gig", "gigs", "concert", "concerts"],
         .init(label: "music", categoryIds: ["4bf58dd8d48988d1e5931735"])),
        (["art", "gallery", "galleries"],
         .init(label: "galleries", categoryIds: ["4bf58dd8d48988d1e2931735"])),
        (["nature", "park", "parks", "garden", "gardens"],
         .init(label: "parks", categoryIds: ["4bf58dd8d48988d163941735", "4bf58dd8d48988d15a941735"])),
        (["history", "architecture", "heritage"],
         .init(label: "heritage", categoryIds: ["4deefb944765f83613cdba6e", "4bf58dd8d48988d12d941735"]))
    ]

    /// The extra searches for `interests`, in interest order, de-duplicated by label and capped.
    public static func searches(for interests: [String]) -> [FoursquarePlacesSource.CategorySearch] {
        var result: [FoursquarePlacesSource.CategorySearch] = []
        for interest in interests {
            for row in matchingRows(for: interest) where !result.contains(where: { $0.label == row.search.label }) {
                guard result.count < maximumSearches else { return result }
                result.append(row.search)
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
