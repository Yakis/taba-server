import GuideKit
import PipelineKit
import Testing

struct InterestMatchTests {
    private func serves(_ interest: String, _ kind: PlaceKind, indoor: Bool = true,
                        labels: [String] = []) -> Bool {
        !InterestMatch.interests(for: [interest], kind: kind, indoor: indoor, searchLabels: labels).isEmpty
    }

    @Test func kindRowsServeTheirInterestWords() {
        let rows: [(String, PlaceKind)] = [
            ("food", .restaurant), ("eat", .cafe), ("eating", .foodHall), ("foodie", .grocery), ("food", .market),
            ("coffee", .cafe), ("cafe", .cafe), ("cafes", .cafe),
            ("pub", .pub), ("pubs", .pub), ("beer", .pub), ("ale", .pub),
            ("bar", .bar), ("bars", .pub), ("cocktails", .bar), ("wine", .pub), ("drinks", .bar),
            ("market", .market), ("markets", .foodHall),
            ("museum", .museum), ("museums", .museum),
            ("history", .landmark), ("architecture", .museum), ("heritage", .landmark),
            ("shopping", .shop), ("shops", .market)
        ]
        for (interest, kind) in rows {
            #expect(serves(interest, kind), "\(interest) should be served by \(kind.rawValue)")
        }
    }

    @Test func searchLabelsServeTheirInterests() {
        let rows: [[String]] = [
            ["music", "bar", "music"], ["gig", "pub", "music"], ["concerts", "restaurant", "music"],
            ["art", "shop", "galleries"], ["gallery", "cafe", "galleries"],
            ["parks", "pub", "parks"], ["nature", "shop", "parks"], ["garden", "cafe", "parks"],
            ["history", "shop", "heritage"], ["architecture", "cafe", "heritage"]
        ]
        for row in rows {
            let (interest, kind, label) = (row[0], PlaceKind(rawValue: row[1]) ?? .other, row[2])
            #expect(serves(interest, kind, labels: [label]), "\(interest) should be served by label \(label)")
            #expect(!serves(interest, kind, labels: ["other"]), "\(interest) must not match another label")
        }
    }

    @Test func musicNeedsAVenueOrAMusicSearch() {
        #expect(serves("music", .venue))
        #expect(!serves("music", .bar))
        #expect(!serves("musical", .venue))
    }

    @Test func artDoesNotMatchArchitectureOrOtherWordParts() {
        #expect(!serves("art", .landmark))
        #expect(serves("art", .museum))
        #expect(!serves("museums", .venue))
        #expect(!serves("pubs", .cafe))
    }

    @Test func photographyCountsOnlyOutdoorsForItsKinds() {
        for kind in [PlaceKind.viewpoint, .landmark, .street, .neighbourhood] {
            #expect(serves("photography", kind, indoor: false), "outdoor \(kind.rawValue) should serve photography")
            #expect(!serves("photography", kind, indoor: true), "indoor \(kind.rawValue) must not serve photography")
        }
        #expect(!serves("photos", .restaurant, indoor: false))
        #expect(serves("photo", .viewpoint, indoor: false))
    }

    @Test func photographyLabelsServeWhateverTheirKind() {
        #expect(serves("photography", .shop, indoor: false, labels: ["heritage"]))
        #expect(serves("photos", .cafe, indoor: true, labels: ["parks"]))
        #expect(!serves("photography", .shop, indoor: false, labels: ["music"]))
    }

    @Test func shoppingAndFoodKindsServeTheirWords() {
        #expect(serves("shopping", .shop, indoor: true))
        #expect(!serves("shopping", .restaurant))
        #expect(serves("food", .grocery))
        #expect(!serves("food", .museum))
    }

    @Test func anythingElseServesNothing() {
        #expect(!serves("Surfing", .restaurant, labels: ["music", "parks", "heritage", "galleries"]))
        #expect(InterestMatch.interests(for: ["", "   ", "!!"], kind: .restaurant, indoor: true,
                                        searchLabels: []).isEmpty)
    }

    @Test func keepsTheTravellersOrderAndSpelling() {
        let interests = ["Shopping", "Food", "Markets"]
        #expect(InterestMatch.interests(for: interests, kind: .market, indoor: true, searchLabels: [])
            == ["Shopping", "Food", "Markets"])
        #expect(InterestMatch.interests(for: ["Markets", "Food"], kind: .market, indoor: true, searchLabels: [])
            == ["Markets", "Food"])
        #expect(InterestMatch.interests(for: ["Live music", "Pubs"], kind: .venue, indoor: true, searchLabels: [])
            == ["Live music"])
    }

    @Test func returnsEachInterestOnce() {
        #expect(InterestMatch.interests(for: ["Pubs", "pubs", "Pubs"], kind: .pub, indoor: true, searchLabels: [])
            == ["Pubs"])
        #expect(InterestMatch.interests(for: ["Food", "Eat", "Food"], kind: .restaurant, indoor: true,
                                        searchLabels: []) == ["Food", "Eat"])
    }

    @Test func aPlaceCanServeSeveralInterests() {
        let served = InterestMatch.interests(for: ["Music", "Food", "Nature", "Pubs"], kind: .venue, indoor: true,
                                             searchLabels: ["music", "parks"])
        #expect(served == ["Music", "Nature"])
    }
}
