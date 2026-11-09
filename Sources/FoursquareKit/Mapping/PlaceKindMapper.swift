import GuideKit

/// Maps Foursquare categories to GuideKit place kinds.
///
/// Matching is on whole words and phrases, so "Barbershops" does not match "bar". Rows are tried in order, so
/// "cafe" is checked before "shop" ("Coffee Shops" is a cafe). The first category that maps wins, in the order
/// Foursquare returns them. Anything else is `other`.
public enum PlaceKindMapper {
    static let table: [(kind: PlaceKind, phrases: [String])] = [
        (.station, ["train station", "railway station", "metro station", "bus station", "station", "stations"]),
        (.lodging, ["hotel", "hotels", "hostel", "hostels", "guest house", "guesthouse", "motel"]),
        (.museum, ["museum", "museums", "art gallery", "galleries"]),
        (.grocery, ["grocery store", "grocery stores", "supermarket", "supermarkets", "grocery", "groceries"]),
        (.viewpoint, ["scenic lookout", "scenic lookouts", "lookout", "lookouts", "viewpoint", "viewpoints"]),
        (.market, ["farmers market", "farmers markets", "flea market", "flea markets", "market", "markets",
                   "marketplace", "marketplaces"]),
        (.foodHall, ["food court", "food courts", "food hall", "food halls"]),
        (.cafe, ["cafe", "cafes", "coffee shop", "coffee shops", "coffee", "cafeteria", "cafeterias",
                 "tea house", "tea houses", "tea room"]),
        (.pub, ["pub", "pubs"]),
        (.venue, ["music venue", "music venues", "concert hall", "concert halls", "jazz club", "jazz clubs",
                  "live music venue"]),
        (.bar, ["bar", "bars"]),
        (.restaurant, ["restaurant", "restaurants", "diner", "pizzeria", "bistro"]),
        (.shop, ["shop", "shops", "store", "stores", "bakery", "bakeries", "boutique", "boutiques"]),
        (.landmark, ["park", "parks", "garden", "gardens", "monument", "monuments", "historic site", "historic sites",
                     "historic and protected site", "protected site", "castle", "castles", "church", "churches",
                     "landmark", "landmarks"])
    ]

    public static func kind(for categories: [FoursquareCategory]) -> PlaceKind {
        for category in categories {
            let label = paddedWords(category.name)
            for row in table where row.phrases.contains(where: { label.contains(" \($0) ") }) {
                return row.kind
            }
        }
        return .other
    }

    /// Lowercase words separated by single spaces, with a space at each end, so phrases match whole words.
    static func paddedWords(_ text: String) -> String {
        let cleaned = text.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
        let words = cleaned.split(separator: " ").joined(separator: " ")
        return " \(words) "
    }
}
