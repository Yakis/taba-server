import Foundation
import GuideKit
import Testing

struct AIRoundTripTests {
    @Test func placeListWithKeyRoundTrips() throws {
        let list = PlaceList(title: "Eat", caption: "Go hungry.", placeIds: [SampleGuide.cafeId], key: .eat)
        #expect(try roundTrip(list) == list)
    }

    @Test func placeListWithoutKeyOmitsTheKey() throws {
        let list = PlaceList(title: "Eat", caption: "Go hungry.", placeIds: [SampleGuide.cafeId])
        let object = try parsedJSON(try encodedJSON(list)) as? [String: Any] ?? [:]
        #expect(!object.keys.contains("key"))
        #expect(try roundTrip(list) == list)
    }

    @Test func planDraftFromTheFixtureRoundTrips() throws {
        let fixture = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
        let draft = FixtureDraft.planDraft(from: fixture)
        #expect(try roundTrip(draft) == draft)
    }

    @Test func planDraftDayRoundTrips() throws {
        let day = try #require(SampleGuide.planDraft().days.first)
        #expect(try roundTrip(day) == day)
    }

    @Test(arguments: 0..<2)
    func planDraftStopRoundTrips(index: Int) throws {
        let stop = try #require(SampleGuide.planDraft().days.first?.stops[index])
        #expect(try roundTrip(stop) == stop)
    }

    @Test func draftListAndSkippedMealRoundTrip() throws {
        let draft = SampleGuide.planDraft()
        let list = try #require(draft.lists.first)
        let skipped = try #require(draft.skippedMeals.first)
        #expect(try roundTrip(list) == list)
        #expect(try roundTrip(skipped) == skipped)
    }

    @Test func guideCopyRoundTrips() throws {
        let copy = SampleGuide.guideCopy()
        #expect(try roundTrip(copy) == copy)
    }

    @Test func guideCopyPartsRoundTrip() throws {
        let copy = SampleGuide.guideCopy()
        #expect(try roundTrip(copy.days[0]) == copy.days[0])
        #expect(try roundTrip(copy.stops[0]) == copy.stops[0])
        #expect(try roundTrip(copy.stops[1]) == copy.stops[1])
        #expect(try roundTrip(copy.places[0]) == copy.places[0])
        #expect(try roundTrip(copy.lists[0]) == copy.lists[0])
        #expect(try roundTrip(copy.notes) == copy.notes)
        #expect(try roundTrip(copy.hero) == copy.hero)
    }

    @Test func researchResultRoundTrips() throws {
        let result = SampleGuide.researchResult()
        #expect(try roundTrip(result) == result)
    }

    @Test func findingWithEveryOptionalEmptyRoundTrips() throws {
        let finding = ResearchFinding(
            id: "f2",
            kind: .closure,
            title: "Bridge closed",
            summary: "Closed for works.",
            startDate: nil,
            endDate: nil,
            times: nil,
            placeName: nil,
            address: nil,
            url: "https://example.com/closure",
            sourceTitle: "Council notice",
            confidence: .low,
            onTripDates: false
        )
        #expect(try roundTrip(finding) == finding)
    }

    @Test(arguments: ListKey.allCases)
    func listKeysRoundTripByRawValue(key: ListKey) throws {
        #expect(try roundTrip(key) == key)
    }

    @Test func suggestedPlaceRoundTrips() throws {
        let place = try #require(SampleGuide.researchResult().suggestedPlaces.first)
        #expect(try roundTrip(place) == place)
    }

    @Test func suggestedPlaceWithoutInterestsDecodesAsNil() throws {
        let json = #"{"name":"Calton Hill","area":"Calton","kind":"viewpoint","why":"Wide views."}"#
        let place = try GuideKit.jsonDecoder().decode(SuggestedPlace.self, from: Data(json.utf8))
        #expect(place.interests == nil)
        #expect(place.kind == .viewpoint)
    }

    @Test func suggestedPlaceWithInterestsDecodesThem() throws {
        let json = #"{"name":"Circus Lane","area":"New Town","kind":"street","why":"Colourful doors.","#
            + #""interests":["Photography"]}"#
        let place = try GuideKit.jsonDecoder().decode(SuggestedPlace.self, from: Data(json.utf8))
        #expect(place.interests == ["Photography"])
        #expect(try roundTrip(place) == place)
    }

    @Test(arguments: FindingKind.allCases)
    func findingKindsRoundTripByRawValue(kind: FindingKind) throws {
        #expect(try roundTrip(kind) == kind)
    }

    @Test(arguments: FindingConfidence.allCases)
    func findingConfidencesRoundTripByRawValue(confidence: FindingConfidence) throws {
        #expect(try roundTrip(confidence) == confidence)
    }

    @Test func unknownFindingKindFailsToDecode() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(FindingKind.self, from: Data(#""rumour""#.utf8))
        }
    }

    @Test func unknownListKeyFailsToDecode() {
        #expect(throws: DecodingError.self) {
            _ = try GuideKit.jsonDecoder().decode(ListKey.self, from: Data(#""shopping""#.utf8))
        }
    }

    @Test func guideWithoutCopyRoundTrips() throws {
        let guide = SampleGuide.make(hero: nil, notes: nil, openQuestions: nil)
        #expect(try roundTrip(guide) == guide)
    }

    /// The keys at the top level of an encoded guide. Nested keys such as a booking's `notes` are not included.
    private func topLevelKeys(_ guide: Guide) throws -> Set<String> {
        let object = try parsedJSON(try encodedJSON(guide)) as? [String: Any] ?? [:]
        return Set(object.keys)
    }

    @Test func guideWithoutCopyOmitsTheNewFieldsFromJSON() throws {
        let keys = try topLevelKeys(SampleGuide.make(hero: nil, notes: nil, openQuestions: nil))
        #expect(!keys.contains("hero"))
        #expect(!keys.contains("notes"))
        #expect(!keys.contains("openQuestions"))
    }

    @Test func guideWithCopyEncodesTheNewFields() throws {
        let keys = try topLevelKeys(SampleGuide.make())
        #expect(keys.isSuperset(of: ["hero", "notes", "openQuestions"]))
    }
}
