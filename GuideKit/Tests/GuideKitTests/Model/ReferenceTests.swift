import GuideKit
import Testing

struct ReferenceTests {
    @Test func flagsStopWithUnknownPlace() {
        let stop = SampleGuide.sightStop(id: "lost", minutes: 45, placeId: "manual:missing")
        let guide = SampleGuide.make(days: [SampleGuide.day(stops: [stop])])
        #expect(guide.structureProblems == [.unknownPlaceReference(placeId: "manual:missing", from: "stop lost")])
    }

    @Test func flagsAlternativeWithUnknownPlace() {
        let stop = SampleGuide.sightStop(
            id: "lost",
            minutes: 45,
            alternative: StopAlternative(placeId: "manual:missing", reason: .rain)
        )
        let guide = SampleGuide.make(days: [SampleGuide.day(stops: [stop])])
        #expect(guide.structureProblems == [
            .unknownPlaceReference(placeId: "manual:missing", from: "stop lost alternative")
        ])
    }

    @Test func flagsListWithUnknownPlace() {
        let list = PlaceList(title: "Eat", caption: "Hungry.", placeIds: [SampleGuide.cafeId, "manual:missing"])
        let guide = SampleGuide.make(lists: [list])
        #expect(guide.structureProblems == [.unknownPlaceReference(placeId: "manual:missing", from: "list Eat")])
    }

    @Test func flagsStayWithUnknownPlace() {
        let guide = SampleGuide.make(stay: SampleGuide.stay(placeId: "manual:missing"))
        #expect(guide.structureProblems == [.unknownPlaceReference(placeId: "manual:missing", from: "stay")])
    }

    @Test func flagsLuggageWithUnknownPlace() {
        let guide = SampleGuide.make(stay: SampleGuide.stay(luggagePlaceId: "manual:missing-store"))
        #expect(guide.structureProblems == [
            .unknownPlaceReference(placeId: "manual:missing-store", from: "stay luggage")
        ])
    }

    @Test func flagsPracticalFactWithUnknownSource() {
        let guide = SampleGuide.make(practical: [SampleGuide.sampleFact(sourceId: "missing-source")])
        #expect(guide.structureProblems == [
            .unknownSourceReference(sourceId: "missing-source", from: "practical")
        ])
    }

    @Test func flagsPlaceFactWithUnknownSource() {
        var places = SampleGuide.samplePlaces()
        places[SampleGuide.cafeId] = SampleGuide.cafe(sourceId: "missing-source")
        let guide = SampleGuide.make(places: places)
        #expect(guide.structureProblems == [
            .unknownSourceReference(sourceId: "missing-source", from: "place \(SampleGuide.cafeId)")
        ])
    }

    @Test func flagsDayOutsideTripDates() {
        let guide = SampleGuide.make(days: [SampleGuide.day(on: "2026-12-01")])
        #expect(guide.structureProblems == [.dayOutsideTripDates(date: SampleGuide.date("2026-12-01"))])
    }

    @Test func flagsDuplicateStopIds() {
        let stops = [
            SampleGuide.sightStop(id: "twin", minutes: 30),
            SampleGuide.sightStop(id: "twin", minutes: 40)
        ]
        let guide = SampleGuide.make(days: [SampleGuide.day(stops: stops)])
        #expect(guide.structureProblems == [.duplicateStopId(stopId: "twin")])
    }
}
