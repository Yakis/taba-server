import Foundation

/// Name tokens for comparing a wanted place name with a name from another source.
public enum NameTokens {
    /// Words too common to tell two places apart: articles, street types, and generic kinds of place. The food and
    /// drink words (ale, inn, tavern, kitchen and so on) name a kind of place, not which one, so "Smithies Ale House"
    /// and "The Ale House" are not the same pub.
    public static let generic: Set<String> = [
        "the", "and", "of", "at", "in", "on", "a", "an",
        "st", "street", "road", "rd", "avenue", "ave", "lane", "ln", "place", "pl",
        "bar", "cafe", "restaurant", "pub", "food", "coffee", "shop", "store",
        "ale", "inn", "tavern", "kitchen", "bistro", "brasserie", "grill", "eatery", "diner",
        "ltd", "limited", "co"
    ]

    /// Words that name a kind of place, such as a hill, a park or a station. Two names that share only these words are
    /// not the same place (see `nameSimilarity`). They are not in `generic`, so a shared place-type word still counts
    /// when other words match too.
    public static let placeTypeWords: Set<String> = [
        "steps", "hill", "garden", "gardens", "park", "square", "bridge", "close", "wynd", "village", "market",
        "gallery", "museum", "church", "cathedral", "castle", "monument", "tower", "gate", "station", "hall", "house",
        "centre", "center"
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
        let wanted = significant(wantedName, cityName: cityName)
        let found = significant(foundName, cityName: cityName)
        if sharesOnlyPlaceTypeWords(wanted, found) { return 0 }
        return similarity(wanted, found)
    }

    /// True when the two token lists share some words, all of them place-type words, and the wanted name has a word
    /// that is not a place-type word. "The Vennel Steps" and "Waverley Steps" share only "steps", so they are not the
    /// same place. A wanted name that is only place-type words, such as "Steps", still matches as before.
    static func sharesOnlyPlaceTypeWords(_ wanted: [String], _ found: [String]) -> Bool {
        let shared = Set(wanted).intersection(found)
        guard !shared.isEmpty, shared.isSubset(of: placeTypeWords) else { return false }
        return wanted.contains { !placeTypeWords.contains($0) }
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
