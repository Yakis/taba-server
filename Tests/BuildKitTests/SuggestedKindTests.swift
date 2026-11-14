@testable import BuildKit
import Foundation
import GuideKit
import Testing

/// One row of the table: a place found as `found` with `foundIndoor`, and research's `suggested` kind.
struct KindCase: Sendable, CustomTestStringConvertible {
    let found: PlaceKind
    let foundIndoor: Bool
    let suggested: PlaceKind
    let expectedKind: PlaceKind
    let expectedIndoor: Bool

    var testDescription: String {
        "\(found)/\(foundIndoor) + \(suggested) -> \(expectedKind)/\(expectedIndoor)"
    }
}

private let kindCases: [KindCase] = [
    KindCase(found: .other, foundIndoor: true, suggested: .restaurant,
             expectedKind: .restaurant, expectedIndoor: true),
    KindCase(found: .other, foundIndoor: true, suggested: .cafe, expectedKind: .cafe, expectedIndoor: true),
    KindCase(found: .other, foundIndoor: true, suggested: .landmark,
             expectedKind: .landmark, expectedIndoor: false),
    KindCase(found: .other, foundIndoor: true, suggested: .market, expectedKind: .market, expectedIndoor: false),
    KindCase(found: .other, foundIndoor: true, suggested: .street, expectedKind: .street, expectedIndoor: false),
    KindCase(found: .landmark, foundIndoor: true, suggested: .viewpoint,
             expectedKind: .viewpoint, expectedIndoor: false),
    KindCase(found: .pub, foundIndoor: true, suggested: .restaurant, expectedKind: .pub, expectedIndoor: true),
    KindCase(found: .landmark, foundIndoor: false, suggested: .museum,
             expectedKind: .landmark, expectedIndoor: false),
    KindCase(found: .other, foundIndoor: true, suggested: .other, expectedKind: .other, expectedIndoor: true)
]

private func fixturePlace() throws -> Place {
    let url = URL(fileURLWithPath: "GuideKit/Tests/GuideKitTests/Fixtures/edinburgh-mock.json")
    let guide = try JSONDecoder().decode(Guide.self, from: Data(contentsOf: url))
    return try #require(guide.places.values.first)
}

/// A copy of a fixture place with the given kind and indoor flag.
private func foundPlace(_ base: Place, kind: PlaceKind, indoor: Bool) -> Place {
    Place(id: base.id, name: base.name, kind: kind, location: base.location, hours: base.hours,
          priceLevel: base.priceLevel, booking: base.booking, indoor: indoor, images: base.images, facts: base.facts,
          copy: base.copy, website: base.website, phone: base.phone, interests: base.interests)
}

struct SuggestedKindTests {
    @Test(arguments: kindCases)
    func aFoundPlaceTakesTheSuggestedKindOnlyWhenTheRulesSaySo(_ row: KindCase) throws {
        let base = try fixturePlace()
        let found = foundPlace(base, kind: row.found, indoor: row.foundIndoor)
        let kept = SuggestionPreparation.keepingSuggestedKind(found, suggested: row.suggested)
        #expect(kept.kind == row.expectedKind)
        #expect(kept.indoor == row.expectedIndoor)
    }

    @Test func everyFieldOtherThanKindAndIndoorSurvives() throws {
        let base = try fixturePlace()
        let found = Place(id: base.id, name: base.name, kind: .other, location: base.location, hours: base.hours,
                          priceLevel: 2, booking: base.booking, indoor: true, images: base.images, facts: base.facts,
                          copy: base.copy, website: "https://example.com/venue", phone: "+00 000 000 0000",
                          interests: ["Photography"])
        let kept = SuggestionPreparation.keepingSuggestedKind(found, suggested: .restaurant)
        #expect(kept.kind == .restaurant)
        #expect(kept.id == found.id)
        #expect(kept.name == found.name)
        #expect(kept.location == found.location)
        #expect(kept.hours == found.hours)
        #expect(kept.priceLevel == 2)
        #expect(kept.booking == found.booking)
        #expect(kept.images == found.images)
        #expect(kept.facts == found.facts)
        #expect(kept.copy == found.copy)
        #expect(kept.website == "https://example.com/venue")
        #expect(kept.phone == "+00 000 000 0000")
        #expect(kept.interests == ["Photography"])
    }
}
