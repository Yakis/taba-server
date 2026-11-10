import FoursquareKit
import GuideKit
import SourcesKit
import Testing

struct PlaceMatcherTests {
    private let matcher = PlaceMatcher(maxDistanceMetres: 200, cityName: "Edinburgh")

    /// Hand-written hits that mirror the probe's failures.
    private func hits(_ places: [String]) throws -> [FoursquarePlace] {
        try Samples.places(HitJSON.search(places))
    }

    @Test func aRoadNamedLikeThePlaceIsRejectedAndTheRealPlaceWins() throws {
        // The probe's first hit was the road "Victoria Street", ranked above "Oink".
        let road = HitJSON.place(
            id: "road", name: "Victoria Street", latitude: 55.951054, longitude: -3.201,
            category: "Road", categoryId: "4bf58dd8d48988d1e1941735"
        )
        let oink = HitJSON.place(
            id: "oink", name: "Oink", latitude: 55.95118, longitude: -3.20102,
            category: "Restaurant", categoryId: "4d4b7105d754a06374d81259"
        )
        let wanted = WantedPlace(
            name: "Oink Victoria Street",
            kind: .restaurant,
            coordinate: Samples.coordinate(55.9510, -3.2010)
        )
        let decision = matcher.choose(for: wanted, among: try hits([road, oink]))
        #expect(decision.best?.fsqPlaceId == "oink")
        #expect(decision.rejected.contains { $0.fsqPlaceId == "road" && $0.reason.contains("road or area") })
    }

    @Test func aFarHitWithTheSameNameIsRejectedForDistance() throws {
        let farAway = HitJSON.place(
            id: "far", name: "M&S Food Stockbridge", latitude: 55.9555, longitude: -3.2100,
            category: "Grocery Store", categoryId: "4bf58dd8d48988d118951735"
        )
        let wanted = WantedPlace(
            name: "M&S Food Stockbridge",
            kind: .grocery,
            coordinate: Samples.coordinate(55.9600, -3.2100)
        )
        let decision = matcher.choose(for: wanted, among: try hits([farAway]))
        #expect(decision.best == nil)
        #expect(decision.rejected.first?.reason.contains("away") == true)
    }

    @Test func aShortenedNameMatchesAndTheMarketIsRejectedOnName() throws {
        // The probe's third hit was "M&S Simply Food", near Stockbridge.
        let stockbridgeMarket = HitJSON.place(
            id: "market", name: "Stockbridge Market", latitude: 55.96036, longitude: -3.2100,
            category: "Farmers Market", categoryId: "4bf58dd8d48988d1fa941735"
        )
        let simplyFood = HitJSON.place(
            id: "simply", name: "M&S Simply Food", latitude: 55.96054, longitude: -3.2100,
            category: "Grocery Store", categoryId: "4bf58dd8d48988d118951735"
        )
        let wanted = WantedPlace(
            name: "M&S Food Stockbridge",
            kind: .grocery,
            coordinate: Samples.coordinate(55.9600, -3.2100)
        )
        let decision = matcher.choose(for: wanted, among: try hits([stockbridgeMarket, simplyFood]))
        #expect(decision.best?.fsqPlaceId == "simply")
        #expect(decision.rejected.contains { $0.fsqPlaceId == "market" && $0.reason.contains("name") })
    }

    @Test func aHitWithExtraWordsMatchesTheWantedName() throws {
        // The probe's "Makars Mash Bar" came back as "Makars Gourmet Mash Bar". "Mash Tun Bar" is a weaker match.
        let makars = HitJSON.place(
            id: "makars", name: "Makars Gourmet Mash Bar", latitude: 55.94609, longitude: -3.2140,
            category: "Pubs", categoryId: "4bf58dd8d48988d11b941735"
        )
        let mashTun = HitJSON.place(
            id: "mashtun", name: "Mash Tun Bar", latitude: 55.94627, longitude: -3.2140,
            category: "Pubs", categoryId: "4bf58dd8d48988d11b941735"
        )
        let wanted = WantedPlace(
            name: "Makars Mash Bar",
            kind: .pub,
            coordinate: Samples.coordinate(55.9460, -3.2140)
        )
        let decision = matcher.choose(for: wanted, among: try hits([mashTun, makars]))
        #expect(decision.best?.fsqPlaceId == "makars")
        #expect(decision.rejected.contains { $0.fsqPlaceId == "mashtun" && $0.reason.contains("ranked below") })
    }

    @Test func aWantedNameWithNoMatchGivesNoPlace() throws {
        // "Edinburgh's Christmas" returned an electrician. The only hit shares no significant word with the name.
        let electrician = HitJSON.place(
            id: "sparks", name: "Edinburgh Electricians Ltd", latitude: 55.95335, longitude: -3.1883,
            category: "Electrician", categoryId: "4bf58dd8d48988d1e1941735"
        )
        let wanted = WantedPlace(
            name: "Edinburgh's Christmas",
            kind: .landmark,
            coordinate: Samples.coordinate(55.9533, -3.1883)
        )
        let decision = matcher.choose(for: wanted, among: try hits([electrician]))
        #expect(decision.best == nil)
        #expect(decision.rejected.first?.reason.contains("name") == true)
    }

    @Test func aHitWithoutACoordinateIsRejected() throws {
        let noPoint = """
        {"fsq_place_id":"nopoint","name":"Oink","categories":[{"fsq_category_id":"x","name":"Restaurant"}]}
        """
        let wanted = WantedPlace(
            name: "Oink",
            kind: .restaurant,
            coordinate: Samples.coordinate(55.9510, -3.2010)
        )
        let decision = matcher.choose(for: wanted, among: [try Samples.place(noPoint)])
        #expect(decision.best == nil)
        #expect(decision.rejected.first?.reason == "no coordinate")
    }

    @Test func noHitsGivesNoPlaceAndNoRejections() {
        let wanted = WantedPlace(
            name: "Oink",
            kind: .restaurant,
            coordinate: Samples.coordinate(55.9510, -3.2010)
        )
        let decision = matcher.choose(for: wanted, among: [])
        #expect(decision.best == nil)
        #expect(decision.rejected.isEmpty)
    }

    @Test func aRoadCategoryDoesNotBlockAPlaceThatIsAStreetKind() throws {
        // The area-category check only applies to shop-like kinds, so a street hit is kept for a street.
        let street = HitJSON.place(
            id: "street", name: "Victoria Street", latitude: 55.951054, longitude: -3.201,
            category: "Road", categoryId: "4bf58dd8d48988d1e1941735"
        )
        let wanted = WantedPlace(
            name: "Victoria Street",
            kind: .street,
            coordinate: Samples.coordinate(55.9510, -3.2010)
        )
        let decision = matcher.choose(for: wanted, among: try hits([street]))
        #expect(decision.best?.fsqPlaceId == "street")
    }

    /// Chooses among one hit at the wanted coordinate, so only the name and category decide.
    private func choose(
        wanted name: String, kind: PlaceKind, hit hitName: String, category: String
    ) throws -> MatchDecision {
        let place = HitJSON.place(id: "hit", name: hitName, latitude: 55.9510, longitude: -3.2010, category: category)
        let wanted = WantedPlace(name: name, kind: kind, coordinate: Samples.coordinate(55.9510, -3.2010))
        return matcher.choose(for: wanted, among: try hits([place]))
    }

    @Test func aPubWithTheSameFoodWordIsNotAnotherPub() throws {
        // "Smithies Ale House" shares only "House" with "The Ale House", so the name check rejects it.
        let decision = try choose(wanted: "Smithies Ale House", kind: .pub, hit: "The Ale House", category: "Pub")
        #expect(decision.best == nil)
        #expect(decision.rejected.first?.reason.contains("name") == true)
    }

    @Test func aShopIsNotAChristmasMarket() throws {
        let decision = try choose(
            wanted: "Edinburgh Christmas Market", kind: .market,
            hit: "The Nutcracker Christmas shop", category: "Gift Shop"
        )
        #expect(decision.best == nil)
        #expect(decision.rejected.first?.reason == "a shop, not a market")
    }

    @Test func aShopIsNotAFoodHall() throws {
        let decision = try choose(
            wanted: "Edinburgh Food Hall", kind: .foodHall,
            hit: "Edinburgh Food Hall Gift Shop", category: "Gift Shop"
        )
        #expect(decision.best == nil)
        #expect(decision.rejected.first?.reason == "a shop, not a food hall")
    }

    @Test func aMarketHitIsNotRejectedAsAShop() throws {
        let decision = try choose(
            wanted: "Stockbridge Market", kind: .market,
            hit: "Stockbridge Sunday Market", category: "Farmers Market"
        )
        #expect(decision.best?.fsqPlaceId == "hit")
    }

    private struct ChoiceCase {
        let wanted: String
        let kind: PlaceKind
        let hit: String
        let category: String
    }

    @Test func theCorrectMatchesStillWinThroughChoose() throws {
        let cases: [ChoiceCase] = [
            .init(wanted: "The Vennel", kind: .viewpoint, hit: "The Vennel Viewpoint Edinburgh Castle",
                  category: "Scenic Lookout"),
            .init(wanted: "Calton Hill", kind: .landmark, hit: "Calton Hill Observatory", category: "Historic Site"),
            .init(wanted: "Stockbridge Market", kind: .market, hit: "Stockbridge Sunday Market",
                  category: "Farmers Market"),
            .init(wanted: "The Café Royal Circle Bar", kind: .pub, hit: "Cafe Royal", category: "Pub"),
            .init(wanted: "Edinburgh's Christmas Market, East Princes Street Gardens", kind: .market,
                  hit: "East Princes Street Gardens", category: "Park"),
            .init(wanted: "The Stockbridge Tap", kind: .pub, hit: "The Stockbridge Tap", category: "Pub"),
            .init(wanted: "Sandy Bell's", kind: .pub, hit: "Sandy Bell's", category: "Pub"),
            .init(wanted: "Clark's Bar", kind: .pub, hit: "Clark's Bar", category: "Bar")
        ]
        for testCase in cases {
            let decision = try choose(
                wanted: testCase.wanted, kind: testCase.kind, hit: testCase.hit, category: testCase.category
            )
            #expect(decision.best?.fsqPlaceId == "hit", "\(testCase.wanted) should match \(testCase.hit)")
        }
    }
}
