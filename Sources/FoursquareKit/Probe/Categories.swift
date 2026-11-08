/// A category swept around the destination centre. The ids come from the public Foursquare category list in the
/// foursquare-go SDK (data/categories.csv), not from the docs site, which this probe could not read.
public struct CategorySweep: Sendable, Hashable {
    public let label: String
    public let categoryName: String
    public let categoryId: String
}

public enum CategorySweeps {
    public static let all: [CategorySweep] = [
        CategorySweep(
            label: "cafés",
            categoryName: "Cafes, Coffee, and Tea Houses",
            categoryId: "63be6904847c3692a84b9bb6"
        ),
        CategorySweep(label: "pubs", categoryName: "Pubs", categoryId: "4bf58dd8d48988d11b941735"),
        CategorySweep(label: "restaurants", categoryName: "Restaurants", categoryId: "4d4b7105d754a06374d81259"),
        CategorySweep(label: "bakeries", categoryName: "Bakeries", categoryId: "4bf58dd8d48988d16a941735"),
        CategorySweep(
            label: "viewpoints",
            categoryName: "Scenic Lookouts",
            categoryId: "4bf58dd8d48988d165941735"
        ),
        CategorySweep(
            label: "markets",
            categoryName: "Farmers Markets",
            categoryId: "4bf58dd8d48988d1fa941735"
        ),
        CategorySweep(label: "museums", categoryName: "Museums", categoryId: "4bf58dd8d48988d181941735"),
        CategorySweep(
            label: "groceries",
            categoryName: "Grocery Stores",
            categoryId: "4bf58dd8d48988d118951735"
        )
    ]
}
