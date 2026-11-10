import Foundation
import GuideKit

/// Which of the traveller's interests a place serves, so the plan can give each interest a stop.
///
/// Interest words are split on non-letters and lowercased, and match a row's word whole: "art" does not match
/// "architecture". A place serves an interest when its kind is in that row, or when Foursquare found it in one of the
/// row's interest searches (`searchLabels`, from `InterestSearches`). Photography's kinds count only outdoors.
public enum InterestMatch {
    private struct Row {
        let words: Set<String>
        let kinds: Set<PlaceKind>
        let searchLabels: Set<String>
        let outdoorOnly: Bool
    }

    private static let rows: [Row] = [
        Row(words: ["food", "eat", "eating", "foodie"],
            kinds: [.restaurant, .cafe, .foodHall, .market, .grocery], searchLabels: [], outdoorOnly: false),
        Row(words: ["coffee", "cafe", "cafes"], kinds: [.cafe], searchLabels: [], outdoorOnly: false),
        Row(words: ["pub", "pubs", "beer", "ale"], kinds: [.pub], searchLabels: [], outdoorOnly: false),
        Row(words: ["bar", "bars", "cocktails", "wine", "drinks"], kinds: [.bar, .pub], searchLabels: [],
            outdoorOnly: false),
        Row(words: ["market", "markets"], kinds: [.market, .foodHall], searchLabels: [], outdoorOnly: false),
        Row(words: ["museum", "museums"], kinds: [.museum], searchLabels: [], outdoorOnly: false),
        Row(words: ["music", "gig", "gigs", "concert", "concerts"], kinds: [.venue], searchLabels: ["music"],
            outdoorOnly: false),
        Row(words: ["art", "gallery", "galleries"], kinds: [.museum], searchLabels: ["galleries"],
            outdoorOnly: false),
        Row(words: ["nature", "park", "parks", "garden", "gardens"], kinds: [], searchLabels: ["parks"],
            outdoorOnly: false),
        Row(words: ["history", "architecture", "heritage"], kinds: [.landmark, .museum],
            searchLabels: ["heritage"], outdoorOnly: false),
        Row(words: ["photography", "photos", "photo"],
            kinds: [.viewpoint, .landmark, .street, .neighbourhood], searchLabels: ["heritage", "parks"],
            outdoorOnly: true),
        Row(words: ["shopping", "shops"], kinds: [.shop, .market], searchLabels: [], outdoorOnly: false)
    ]

    /// The traveller's own interest strings, as written and in their order, that this place serves. Each interest
    /// appears once, even when it is repeated. Anything that matches no row serves nothing.
    public static func interests(for interests: [String], kind: PlaceKind, indoor: Bool,
                                 searchLabels: [String]) -> [String] {
        let labels = Set(searchLabels)
        var seen = Set<String>()
        return interests.filter { interest in
            let words = words(in: interest)
            guard !words.isEmpty else { return false }
            let served = rows.contains { row in
                guard !row.words.isDisjoint(with: words) else { return false }
                let byKind = row.kinds.contains(kind) && (!row.outdoorOnly || !indoor)
                return byKind || !row.searchLabels.isDisjoint(with: labels)
            }
            return served && seen.insert(words.sorted().joined(separator: " ")).inserted
        }
    }

    private static func words(in interest: String) -> Set<String> {
        Set(interest.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
    }
}
