import Foundation
import GuideKit
import Testing

struct EdinburghGuideFixtureTests {
    /// The committed fixture, found from this file: .../Tests/GuideKitTests/Model/ -> .../Tests/GuideKitTests/Fixtures.
    private static let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/edinburgh-guide.json")

    private func loadGuide() throws -> Guide {
        try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
    }

    private func loadMock() throws -> Guide {
        try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
    }

    @Test func committedFileMatchesTheFinishedGuide() throws {
        let encoded = try GuideKit.jsonEncoder().encode(FinishedGuide.make())
        if ProcessInfo.processInfo.environment["TABA_WRITE_FIXTURES"] == "1" {
            try encoded.write(to: Self.fixtureURL)
            Issue.record("Rewrote edinburgh-guide.json; run the tests again without TABA_WRITE_FIXTURES")
            return
        }
        #expect(encoded == (try Fixture.edinburghGuideData()))
    }

    @Test func fixtureDecodesAndRoundTripsByteForByte() throws {
        let original = try Fixture.edinburghGuideData()
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: original)
        #expect(try GuideKit.jsonEncoder().encode(guide) == original)
    }

    @Test func fixtureHasNoStructureProblems() throws {
        let guide = try loadGuide()
        #expect(guide.structureProblems.isEmpty)
        try guide.validateStructure()
    }

    @Test func fixtureIsReadyAndFinished() throws {
        let guide = try loadGuide()
        #expect(guide.status == .ready)
        #expect(guide.hero != nil)
        #expect(guide.notes != nil)
        #expect(guide.openQuestions?.count == 3)
        #expect(guide.days.count == 3)
        #expect(guide.days.allSatisfy { $0.weather != nil })
    }

    @Test func everyStopAfterTheFirstWithAPlaceAfterAPlaceHasAWalkLeg() throws {
        let guide = try loadGuide()
        for day in guide.days {
            for (index, stop) in day.stops.enumerated() {
                guard index > 0 else {
                    #expect(stop.legFromPrevious == nil, "\(stop.id) starts the day")
                    continue
                }
                let previous = day.stops[index - 1]
                if stop.placeId != nil, previous.placeId != nil {
                    let leg = try #require(stop.legFromPrevious, "\(stop.id) needs a walk")
                    #expect(leg.mode == .walk)
                    #expect(leg.minutes > 0)
                } else {
                    #expect(stop.legFromPrevious == nil, "\(stop.id) has no walk")
                }
            }
        }
    }

    @Test func sameTripAsTheMock() throws {
        let guide = try loadGuide()
        let mock = try loadMock()
        #expect(guide.trip == mock.trip)
        #expect(guide.bookings == mock.bookings)
        #expect(guide.stay == mock.stay)
        #expect(Set(guide.places.keys) == Set(mock.places.keys))
        // The sample adds websites to a few places; everything else about each place is the mock's.
        for (id, place) in guide.places {
            let original = try #require(mock.places[id])
            #expect(place.website == nil || original.website == nil, "\(id) website comes from the sample")
            #expect(place.name == original.name && place.kind == original.kind && place.location == original.location)
            #expect(place.hours == original.hours && place.facts == original.facts && place.copy == original.copy)
            #expect(place.priceLevel == original.priceLevel && place.booking == original.booking)
        }
        #expect(guide.places.values.filter { $0.website != nil }.count == 3)
        #expect(guide.tasting == mock.tasting)
        let lists = guide.lists.map { PlaceList(title: $0.title, caption: $0.caption, placeIds: $0.placeIds) }
        #expect(lists == mock.lists)
    }
}
