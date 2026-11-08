import Foundation

/// Name tokens for comparing a wanted place name with a name from another source.
public enum NameTokens {
    /// Words too common to tell two places apart: articles, street types and generic kinds of place.
    public static let generic: Set<String> = [
        "the", "and", "of", "at", "in", "on", "a", "an",
        "st", "street", "road", "rd", "avenue", "ave", "lane", "ln", "place", "pl",
        "bar", "cafe", "restaurant", "pub", "food", "coffee", "shop", "store",
        "ltd", "limited", "co"
    ]

    /// The lowest name similarity that counts as the same place.
    public static let acceptableSimilarity = 0.5

    /// Significant tokens for a name: lowercase, no diacritics or punctuation, "&" read as "and", with generic words
    /// and the city name left out, each token once. A name made only of generic words keeps all of its words.
    public static func significant(_ name: String, cityName: String? = nil) -> [String] {
        let allWords = words(in: name)
        let cityWords = Set(cityName.map { words(in: $0) } ?? [])
        var seen = Set<String>()
        let kept = allWords.filter { word in
            !generic.contains(word) && !cityWords.contains(word) && seen.insert(word).inserted
        }
        return kept.isEmpty ? unique(allWords) : kept
    }

    /// The similarity of two names as an F1 score from 0 to 1. It is 1 when the significant tokens match exactly,
    /// and 0 when they share none.
    public static func nameSimilarity(_ wantedName: String, _ foundName: String, cityName: String? = nil) -> Double {
        similarity(significant(wantedName, cityName: cityName), significant(foundName, cityName: cityName))
    }

    /// F1 overlap of two token lists: the share of wanted tokens found, balanced against the share of found tokens
    /// that were wanted.
    public static func similarity(_ wanted: [String], _ found: [String]) -> Double {
        let wantedSet = Set(wanted)
        let foundSet = Set(found)
        let shared = Double(wantedSet.intersection(foundSet).count)
        guard shared > 0 else { return 0 }
        let recall = shared / Double(wantedSet.count)
        let precision = shared / Double(foundSet.count)
        return 2 * recall * precision / (recall + precision)
    }

    /// Lowercase words with diacritics and punctuation removed. "&" becomes "and", and a possessive "'s" is dropped,
    /// so "Edinburgh's" is the one word "edinburgh".
    static func words(in name: String) -> [String] {
        let characters = Array(name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
        var cleaned = ""
        var index = 0
        while index < characters.count {
            if isPossessive(characters, at: index) {
                index += 2
                continue
            }
            let character = characters[index]
            if character == "&" {
                cleaned += " and "
            } else if character.isLetter || character.isNumber {
                cleaned.append(character)
            } else {
                cleaned.append(" ")
            }
            index += 1
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    /// True when the apostrophe at `index` starts a possessive "'s" that ends the word.
    private static func isPossessive(_ characters: [Character], at index: Int) -> Bool {
        let apostrophes: Set<Character> = ["'", "\u{2019}"]
        guard index + 1 < characters.count else { return false }
        guard apostrophes.contains(characters[index]), characters[index + 1] == "s" else { return false }
        let after = index + 2
        return after == characters.count || !characters[after].isLetter
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }
}
