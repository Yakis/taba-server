import FoursquareKit
import GuideKit
import Testing

struct PlaceKindMapperTests {
    private func kind(of label: String) -> PlaceKind {
        PlaceKindMapper.kind(for: [FoursquareCategory(id: "x", name: label)])
    }

    @Test(arguments: [
        ("Pubs", PlaceKind.pub),
        ("Irish Pubs", .pub),
        ("Cocktail Bars", .bar),
        ("Beer Bars", .bar),
        ("Cafes, Coffee, and Tea Houses", .cafe),
        ("Coffee Shops", .cafe),
        ("Farmers Markets", .market),
        ("Scenic Lookouts", .viewpoint),
        ("Museums", .museum),
        ("Grocery Stores", .grocery),
        ("Train Station", .station),
        ("Bakeries", .shop),
        ("Food Courts", .foodHall),
        ("Hotels", .lodging),
        ("Restaurants", .restaurant),
        ("Afghan Restaurants", .restaurant)
    ])
    func mapsCategoryLabelsToKinds(label: String, expected: PlaceKind) {
        #expect(kind(of: label) == expected)
    }

    @Test func wholeWordsOnly() {
        // "Barbershops" must not become a bar, and "Basketball Court" must not become a food court.
        #expect(kind(of: "Barbershops") == .other)
        #expect(kind(of: "Basketball Courts") == .other)
    }

    @Test func unknownLabelIsOther() {
        #expect(kind(of: "Public Bathrooms") == .other)
    }

    @Test func firstMappedCategoryWins() {
        let categories = [
            FoursquareCategory(id: "a", name: "Public Bathrooms"),
            FoursquareCategory(id: "b", name: "Pubs"),
            FoursquareCategory(id: "c", name: "Museums")
        ]
        #expect(PlaceKindMapper.kind(for: categories) == .pub)
    }

    @Test func noCategoriesIsOther() {
        #expect(PlaceKindMapper.kind(for: []) == .other)
    }
}
