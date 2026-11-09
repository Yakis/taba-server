import GuideKit
import Testing

struct GuideAssemblyTests {
    private static let stopCopy = [
        GuideCopyStop(
            id: "d1-s1",
            title: "Market walk",
            body: "Look at the stalls.",
            actionLabel: "Walk to the market"
        ),
        GuideCopyStop(id: "d1-s2", title: "Lunch", body: "Soup and bread.", actionLabel: nil),
        GuideCopyStop(id: "d1-s3", title: "Transfer", body: "Take the bus.", actionLabel: "Walk to the bus")
    ]

    /// Three stops in the planner's order, which is not time order: the market at 15:00 comes first in the plan.
    private func outOfOrderDraft() -> PlanDraft {
        let day = PlanDraftDay(
            date: SampleGuide.date("2026-11-22"),
            theme: "Settle in",
            stops: [
                PlanDraftStop(
                    id: "d1-s1",
                    placeId: SampleGuide.marketId,
                    kind: .sight,
                    mealSlot: nil,
                    start: SampleGuide.time("15:00"),
                    minutes: 45,
                    flexible: false,
                    alternative: nil,
                    reason: "Market.",
                    findingIds: []
                ),
                PlanDraftStop(
                    id: "d1-s2",
                    placeId: SampleGuide.cafeId,
                    kind: .meal,
                    mealSlot: .lunch,
                    start: SampleGuide.time("13:15"),
                    minutes: 60,
                    flexible: true,
                    alternative: nil,
                    reason: "Lunch.",
                    findingIds: []
                ),
                PlanDraftStop(
                    id: "d1-s3",
                    placeId: nil,
                    kind: .travel,
                    mealSlot: nil,
                    start: SampleGuide.time("09:30"),
                    minutes: 20,
                    flexible: false,
                    alternative: nil,
                    reason: "Transfer.",
                    findingIds: []
                )
            ]
        )
        return PlanDraft(
            days: [day],
            lists: [DraftList(key: .eat, placeIds: [SampleGuide.cafeId])],
            skippedMeals: [],
            openQuestions: ["Check the market hours."],
            changes: []
        )
    }

    private func completeCopy(
        stops: [GuideCopyStop] = GuideAssemblyTests.stopCopy,
        days: [GuideCopyDay] = [
            GuideCopyDay(date: SampleGuide.date("2026-11-22"), title: "Settle in", summary: "A day.")
        ],
        places: [GuideCopyPlace] = [
            GuideCopyPlace(id: SampleGuide.cafeId, tag: "Coffee", blurb: "A quiet room."),
            GuideCopyPlace(id: SampleGuide.marketId, tag: "Market", blurb: "Stalls and bread.")
        ],
        lists: [GuideCopyList] = [GuideCopyList(key: .eat, title: "Eat", caption: "Go hungry.")]
    ) -> GuideCopy {
        GuideCopy(
            hero: SampleGuide.hero(),
            days: days,
            stops: stops,
            places: places,
            lists: lists,
            tasting: [TasteItem(name: "Sample bake", note: "Ask for it warm.")],
            notes: SampleGuide.notes()
        )
    }

    private func assemble(
        _ draft: PlanDraft,
        _ copy: GuideCopy,
        weather: [LocalDate: DayOutlook] = [:]
    ) -> AssemblyResult {
        let facts = TripFacts(
            trip: SampleGuide.trip(),
            bookings: [],
            stay: SampleGuide.stay(),
            places: SampleGuide.samplePlaces(),
            practical: [],
            sources: []
        )
        return GuideAssembler(walkTimes: FixedWalk(fixedMinutes: 7)).assemble(
            id: "sample",
            facts: facts,
            draft: draft,
            copy: copy,
            weather: weather
        )
    }

    private static let sunnyOutlook = DayOutlook(
        summary: "Bright and cold",
        highCelsius: 6,
        lowCelsius: 1,
        rainChance: 10,
        isForecast: true
    )

    @Test func weatherLandsOnItsDay() {
        let weather = [SampleGuide.date("2026-11-22"): Self.sunnyOutlook]
        let result = assemble(outOfOrderDraft(), completeCopy(), weather: weather)
        #expect(result.guide.days[0].weather == Self.sunnyOutlook)
    }

    @Test func dayWithNoWeatherEntryGetsNone() {
        let weather = [SampleGuide.date("2026-11-23"): Self.sunnyOutlook]
        let result = assemble(outOfOrderDraft(), completeCopy(), weather: weather)
        #expect(result.guide.days[0].weather == nil)
    }

    @Test func weatherDefaultsToNoneForEveryDay() {
        let result = assemble(outOfOrderDraft(), completeCopy())
        #expect(result.guide.days.allSatisfy { $0.weather == nil })
    }

    @Test func stopsAreSortedByTimeAndRenumbered() {
        let result = assemble(outOfOrderDraft(), completeCopy())
        let stops = result.guide.days[0].stops
        #expect(stops.map(\.id) == ["d1-s1", "d1-s2", "d1-s3"])
        #expect(stops.map(\.copy.title) == ["Transfer", "Lunch", "Market walk"])
        #expect(result.stopIds == ["d1-s1": "d1-s3", "d1-s2": "d1-s2", "d1-s3": "d1-s1"])
        #expect(result.problems.isEmpty)
    }

    @Test func legsOnlyJoinConsecutiveStopsThatBothHavePlaces() {
        let result = assemble(outOfOrderDraft(), completeCopy())
        let stops = result.guide.days[0].stops
        // The transfer has no place, so the lunch after it has no walk from it.
        #expect(stops[0].legFromPrevious == nil)
        #expect(stops[1].legFromPrevious == nil)
        // Lunch to the market is one walk, timed by the walk times passed in.
        #expect(stops[2].legFromPrevious?.minutes == 7)
        #expect(stops[2].legFromPrevious?.mode == .walk)
    }

    @Test func copyLandsOnPlacesListsHeroNotesAndOpenQuestions() {
        let result = assemble(outOfOrderDraft(), completeCopy())
        let guide = result.guide
        #expect(guide.places[SampleGuide.cafeId]?.copy == PlaceCopy(tag: "Coffee", blurb: "A quiet room."))
        #expect(guide.lists == [
            PlaceList(title: "Eat", caption: "Go hungry.", placeIds: [SampleGuide.cafeId], key: .eat)
        ])
        #expect(guide.hero == SampleGuide.hero())
        #expect(guide.notes == SampleGuide.notes())
        #expect(guide.openQuestions == ["Check the market hours."])
        #expect(guide.tasting == [TasteItem(name: "Sample bake", note: "Ask for it warm.")])
    }

    @Test func guideIsADraftAtVersionOne() {
        let guide = assemble(outOfOrderDraft(), completeCopy()).guide
        #expect(guide.status == .draft)
        #expect(guide.version == 1)
    }

    @Test func missingStopCopyIsReportedAndLeftEmpty() {
        let copy = completeCopy(stops: Array(GuideAssemblyTests.stopCopy.dropFirst()))
        let result = assemble(outOfOrderDraft(), copy)
        #expect(result.problems == [.missingCopy(.stop("d1-s1"))])
        #expect(result.guide.days[0].stops[2].copy == StopCopy(title: "", body: "", actionLabel: nil))
    }

    @Test func extraStopCopyIsReportedAndDropped() {
        let extra = GuideCopyStop(id: "ghost", title: "Ghost", body: "Boo.", actionLabel: nil)
        let result = assemble(outOfOrderDraft(), completeCopy(stops: GuideAssemblyTests.stopCopy + [extra]))
        #expect(result.problems == [.extraCopy(.stop("ghost"))])
        #expect(result.guide.days[0].stops.count == 3)
    }

    @Test func repeatedStopCopyKeepsTheFirstAndIsReported() {
        let repeated = GuideCopyStop(id: "d1-s2", title: "Second lunch", body: "Again.", actionLabel: nil)
        let result = assemble(outOfOrderDraft(), completeCopy(stops: GuideAssemblyTests.stopCopy + [repeated]))
        #expect(result.problems == [.duplicateCopy(.stop("d1-s2"))])
        #expect(result.guide.days[0].stops[1].copy.title == "Lunch")
    }

    @Test func listKeyWithNoCopyIsReportedAndKeptEmpty() {
        let result = assemble(outOfOrderDraft(), completeCopy(lists: []))
        #expect(result.problems == [.missingCopy(.list(.eat))])
        #expect(result.guide.lists == [
            PlaceList(title: "", caption: "", placeIds: [SampleGuide.cafeId], key: .eat)
        ])
    }

    @Test func lodgingWithNoCopyIsNotReportedAndKeepsItsOwnCopy() {
        let checkIn = PlanDraftStop(
            id: "d1-s1",
            placeId: SampleGuide.hotelId,
            kind: .logistics,
            mealSlot: nil,
            start: SampleGuide.time("15:00"),
            minutes: 30,
            flexible: false,
            alternative: nil,
            reason: "Check in.",
            findingIds: []
        )
        let draft = PlanDraft(
            days: [PlanDraftDay(date: SampleGuide.date("2026-11-22"), theme: "Arrive", stops: [checkIn])],
            lists: [],
            skippedMeals: [],
            openQuestions: [],
            changes: []
        )
        let copy = completeCopy(
            stops: [GuideCopyStop(id: "d1-s1", title: "Check in", body: "Drop your bags.", actionLabel: nil)],
            places: [],
            lists: []
        )
        let result = assemble(draft, copy)
        #expect(result.problems.isEmpty)
        #expect(result.guide.places[SampleGuide.hotelId]?.copy == SampleGuide.hotel().copy)
    }

    @Test func extraListCopyIsReported() {
        let extra = GuideCopyList(key: .groceries, title: "Groceries", caption: "Edible souvenirs.")
        let copy = completeCopy(lists: [GuideCopyList(key: .eat, title: "Eat", caption: "Go hungry."), extra])
        #expect(assemble(outOfOrderDraft(), copy).problems == [.extraCopy(.list(.groceries))])
    }

    @Test func missingDayCopyIsReportedAndLeftEmpty() {
        let result = assemble(outOfOrderDraft(), completeCopy(days: []))
        #expect(result.problems == [.missingCopy(.day(SampleGuide.date("2026-11-22")))])
        #expect(result.guide.days[0].copy == DayCopy(title: "", summary: ""))
    }

    @Test func extraPlaceCopyIsReportedAndDropped() {
        let extra = GuideCopyPlace(id: "manual:ghost", tag: "Ghost", blurb: "Not in the plan.")
        let copy = completeCopy(places: [
            GuideCopyPlace(id: SampleGuide.cafeId, tag: "Coffee", blurb: "A quiet room."),
            GuideCopyPlace(id: SampleGuide.marketId, tag: "Market", blurb: "Stalls and bread."),
            extra
        ])
        let result = assemble(outOfOrderDraft(), copy)
        #expect(result.problems == [.extraCopy(.place("manual:ghost"))])
        #expect(result.guide.places["manual:ghost"] == nil)
    }

    @Test func aPlaceTheListsUseWithNoCopyIsReported() {
        let copy = completeCopy(places: [GuideCopyPlace(id: SampleGuide.marketId, tag: "Market", blurb: "Stalls.")])
        let result = assemble(outOfOrderDraft(), copy)
        #expect(result.problems == [.missingCopy(.place(SampleGuide.cafeId))])
        #expect(result.guide.places[SampleGuide.cafeId]?.copy == nil)
    }
}
