import GuideKit

/// Sample copy, notes and planner output for the AI types. Like `SampleGuide`, these describe made-up places.
extension SampleGuide {
    static func hero() -> GuideHero {
        GuideHero(title: "Sample Walk", subtitle: "A made-up trip for model tests.", tagline: "Short and dry.")
    }

    static func notes() -> GuideNotes {
        GuideNotes(
            weather: "Cold, with a chance of rain.",
            light: "Sunset is early.",
            backupPlan: "Indoor stops come first.",
            rules: "Eat when you are hungry."
        )
    }

    static func planDraft() -> PlanDraft {
        PlanDraft(
            days: [
                PlanDraftDay(
                    date: date("2026-11-22"),
                    theme: "Settle in",
                    stops: [
                        PlanDraftStop(
                            id: "d1-s1",
                            placeId: cafeId,
                            kind: .meal,
                            mealSlot: .lunch,
                            start: time("13:15"),
                            minutes: 60,
                            flexible: true,
                            alternative: StopAlternative(placeId: marketId, reason: .closed),
                            reason: "Lunch near the stay.",
                            findingIds: []
                        ),
                        PlanDraftStop(
                            id: "d1-s2",
                            placeId: nil,
                            kind: .rest,
                            mealSlot: nil,
                            start: time("17:00"),
                            minutes: 30,
                            flexible: true,
                            alternative: nil,
                            reason: "Rest before dinner.",
                            findingIds: ["f1"]
                        )
                    ]
                )
            ],
            lists: [DraftList(key: .eat, placeIds: [cafeId, marketId])],
            skippedMeals: [SkippedMeal(date: date("2026-11-22"), slot: .dinner, reason: "Late lunch.")],
            openQuestions: ["Is the market open on Sunday?"],
            changes: []
        )
    }

    static func guideCopy() -> GuideCopy {
        GuideCopy(
            hero: hero(),
            days: [GuideCopyDay(date: date("2026-11-22"), title: "Settle in", summary: "Lunch, then rest.")],
            stops: [
                GuideCopyStop(id: "d1-s1", title: "Lunch", body: "Soup and bread.", actionLabel: "Walk to the cafe"),
                GuideCopyStop(id: "d1-s2", title: "Rest", body: "Put your feet up.", actionLabel: nil)
            ],
            places: [GuideCopyPlace(id: cafeId, tag: "Coffee", blurb: "A quiet room near the market.")],
            lists: [GuideCopyList(key: .eat, title: "Eat", caption: "Go hungry.")],
            tasting: [TasteItem(name: "Sample bake", note: "Ask for it warm.")],
            notes: notes()
        )
    }

    static func researchResult() -> ResearchResult {
        ResearchResult(
            findings: [
                ResearchFinding(
                    id: "f1",
                    kind: .market,
                    title: "Sample market",
                    summary: "Open on Sundays.",
                    startDate: date("2026-11-22"),
                    endDate: nil,
                    times: "09:00-17:00",
                    placeName: "Sample Market",
                    address: nil,
                    url: "https://example.com/market",
                    sourceTitle: "Sample market page",
                    confidence: .high,
                    onTripDates: true
                )
            ],
            suggestedPlaces: [
                SuggestedPlace(name: "Sample Viewpoint", area: "North", kind: .viewpoint, why: "Wide views.")
            ],
            searchNotes: "Could not confirm the winter hours."
        )
    }
}
