import Foundation
import GuideKit

/// Tasting names that are only a category of food or drink, such as "Bread" or "Indian snacks". A tasting item must be
/// a named local speciality (write.md rule 8), so a category is reported to the writer and, if it is still there after
/// the rewrite, removed before the guide is used.
enum GenericTasting {
    /// Category words, singular and plural. A name is generic only when at least one of its words is one of these.
    static let categoryNouns: Set<String> = [
        "bread", "cheese", "cheeses", "vegetable", "vegetables", "veg", "fruit", "fruits", "meat", "meats", "fish",
        "seafood", "coffee", "coffees", "tea", "teas", "beer", "beers", "ale", "ales", "wine", "wines", "cider",
        "ciders", "spirit", "spirits", "cocktail", "cocktails", "cake", "cakes", "pastry", "pastries", "snack",
        "snacks", "sweet", "sweets", "chocolate", "chocolates", "sandwich", "sandwiches", "soup", "soups", "produce",
        "dessert", "desserts", "food", "foods", "drink", "drinks", "bake", "bakes"
    ]

    /// Words that may qualify a category ("fresh bread", "Indian snacks") without naming anything. A name made only of
    /// these and category words is generic. Cuisine adjectives are here too, since "Indian snacks" names no dish.
    static let modifiers: Set<String> = [
        "local", "fresh", "artisan", "artisanal", "craft", "homemade", "home", "made", "hot", "real", "regional",
        "traditional", "seasonal", "organic", "small", "street", "baked", "cured", "roast", "good", "specialty",
        "speciality", "indian", "chinese", "italian", "french", "thai", "japanese", "korean", "mexican", "spanish",
        "turkish", "greek", "lebanese", "vietnamese", "caribbean", "american", "british", "english"
    ]

    /// Whether a tasting name is a category rather than a named speciality. The name is split into letter words, so
    /// hyphens, "&" and punctuation separate words, and "and" is ignored. It is generic when every word is a category
    /// word or a modifier, and at least one is a category word. "Bread", "Indian snacks" and "Craft beer" are generic;
    /// "Parkin", "Earl Grey tea" (the name word is not a modifier) and "Fish and chips" are not.
    static func isGeneric(_ name: String) -> Bool {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init).filter { $0 != "and" }
        var hasCategory = false
        for word in words {
            if categoryNouns.contains(word) {
                hasCategory = true
            } else if !modifiers.contains(word) {
                return false
            }
        }
        return hasCategory
    }
}

extension GuideCopy {
    /// The copy without its generic tasting items. The writer is asked to replace them first; this removes any that
    /// remain, so a category is never shipped as a tasting item.
    func removingGenericTasting() -> GuideCopy {
        GuideCopy(hero: hero, days: days, stops: stops, places: places, lists: lists,
                  tasting: tasting.filter { !GenericTasting.isGeneric($0.name) }, notes: notes)
    }
}
