/// How a stop is labelled and coloured on the page: its eyebrow words and its CSS class. Mirrors the app's
/// `KindStyle`. Meals are `meal` (steel), drinks `drink` (coral), sights `sight`, and rest, practical and travel
/// are `quiet`.
struct StopKindStyle: Equatable {
    /// Title case, for example "Lunch" or "Sight". The page uppercases it with CSS.
    let eyebrow: String
    /// One of "meal", "drink", "sight" or "quiet".
    let cssClass: String

    static func forStop(_ stop: Stop) -> StopKindStyle {
        switch stop.kind {
        case .meal:
            StopKindStyle(eyebrow: mealEyebrow(stop.mealSlot), cssClass: "meal")
        case .drink:
            StopKindStyle(eyebrow: "Drink", cssClass: "drink")
        case .sight:
            StopKindStyle(eyebrow: "Sight", cssClass: "sight")
        case .rest:
            StopKindStyle(eyebrow: "Rest", cssClass: "quiet")
        case .logistics:
            StopKindStyle(eyebrow: "Practical", cssClass: "quiet")
        case .travel:
            StopKindStyle(eyebrow: "Travel", cssClass: "quiet")
        }
    }

    private static func mealEyebrow(_ slot: MealSlot?) -> String {
        switch slot {
        case .breakfast?: "Breakfast"
        case .lunch?: "Lunch"
        case .dinner?: "Dinner"
        case nil: "Meal"
        }
    }
}
