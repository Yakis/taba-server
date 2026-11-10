import Foundation
import GuideKit

/// Which of the traveller's interests a place serves, so the plan can give each interest a stop.
///
/// Interest words are split on non-letters and lowercased, and match a row's word whole: "art" does not match
/// "architecture". A place serves an interest when its kind is in that row, or when Foursquare found it in one of the
/// row's interest searches (`searchLabels`, from `InterestSearches`). Photography's kinds count only outdoors.
///
/// Research can also say which interest a suggested place serves, with the label made by `interestLabel(for:)`.
/// Such a label serves the traveller's interest with the same words, whatever the kind or indoor, so a place
/// research suggests for "Photography" serves Photography even when its kind is in no row.
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
        Row(words: ["photography", "photos", "photo", "views", "view", "viewpoint", "viewpoints"],
            kinds: [.viewpoint, .landmark, .street, .neighbourhood], searchLabels: ["heritage", "parks", "views"],
            outdoorOnly: true),
        Row(words: ["shopping", "shops"], kinds: [.shop, .market], searchLabels: [], outdoorOnly: false)
    ]

    /// The search label that research gives a suggested place for the traveller's interest, as written in the trip.
    public static func interestLabel(for interest: String) -> String {
        interestLabelPrefix + interest
    }

    /// The traveller's own interest strings, as written and in their order, that this place serves. Each interest
    /// appears once, even when it is repeated. Anything that matches no row and no "interest:" label serves nothing.
    public static func interests(for interests: [String], kind: PlaceKind, indoor: Bool,
                                 searchLabels: [String]) -> [String] {
        let labels = Set(searchLabels)
        let researched = Set(searchLabels.compactMap { label -> String? in
            guard label.hasPrefix(interestLabelPrefix) else { return nil }
            return wordKey(words(in: String(label.dropFirst(interestLabelPrefix.count))))
        })
        var seen = Set<String>()
        return interests.filter { interest in
            let words = words(in: interest)
            guard !words.isEmpty else { return false }
            let served = researched.contains(wordKey(words)) || rows.contains { row in
                guard !row.words.isDisjoint(with: words) else { return false }
                let byKind = row.kinds.contains(kind) && (!row.outdoorOnly || !indoor)
                return byKind || !row.searchLabels.isDisjoint(with: labels)
            }
            return served && seen.insert(wordKey(words)).inserted
        }
    }

    private static let interestLabelPrefix = "interest:"

    private static func words(in interest: String) -> Set<String> {
        Set(interest.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
    }

    /// The words of an interest, sorted and joined, so two interests with the same words give the same key.
    private static func wordKey(_ words: Set<String>) -> String {
        words.sorted().joined(separator: " ")
    }
}
