import GuideKit

/// Turns the Edinburgh fixture back into the plan and copy that would have made it. Assembling the inverse must give
/// the fixture back, which tests the assembler against real data.
enum FixtureDraft {
    /// The fixture's days and stops as a plan. Day themes are the day titles, and every reason is "fixture".
    static func planDraft(from guide: Guide) -> PlanDraft {
        let days = guide.days.map { day in
            PlanDraftDay(
                date: day.date,
                theme: day.copy.title,
                stops: day.stops.map { stop in
                    PlanDraftStop(
                        id: stop.id,
                        placeId: stop.placeId,
                        kind: stop.kind,
                        mealSlot: stop.mealSlot,
                        start: stop.start,
                        minutes: stop.minutes,
                        flexible: stop.flexible,
                        alternative: stop.alternative,
                        reason: "fixture",
                        findingIds: []
                    )
                }
            )
        }
        let lists = guide.lists.map { DraftList(key: listKey(for: $0.title), placeIds: $0.placeIds) }
        return PlanDraft(days: days, lists: lists, skippedMeals: [], openQuestions: [], changes: [])
    }

    /// The fixture's words as copy. The hero and notes are invented, because the fixture has none.
    static func copy(from guide: Guide) -> GuideCopy {
        let days = guide.days.map { day in
            GuideCopyDay(date: day.date, title: day.copy.title, summary: day.copy.summary)
        }
        let stops = guide.days.flatMap(\.stops).map { stop in
            GuideCopyStop(
                id: stop.id,
                title: stop.copy.title,
                body: stop.copy.body,
                actionLabel: stop.copy.actionLabel
            )
        }
        let places = guide.places.values.sorted { $0.id < $1.id }.compactMap { place -> GuideCopyPlace? in
            guard let copy = place.copy else { return nil }
            return GuideCopyPlace(id: place.id, tag: copy.tag, blurb: copy.blurb)
        }
        let lists = guide.lists.map { list in
            GuideCopyList(key: listKey(for: list.title), title: list.title, caption: list.caption)
        }
        return GuideCopy(
            hero: GuideHero(title: "Edinburgh", subtitle: "Three days of old stones.", tagline: "Go slowly."),
            days: days,
            stops: stops,
            places: places,
            lists: lists,
            tasting: guide.tasting,
            notes: GuideNotes(weather: "Cold.", light: "Early sunsets.", backupPlan: "Indoors.", rules: "Be kind.")
        )
    }

    /// The pick-list key for a fixture list title such as "Eat".
    static func listKey(for title: String) -> ListKey {
        guard let key = ListKey(rawValue: title.lowercased()) else {
            preconditionFailure("No list key for fixture list \(title)")
        }
        return key
    }
}
