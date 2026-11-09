/// Builds a `Guide` from a checked plan and its copy, with the trip's facts.
///
/// The plan is sorted by time within each day and its stops are renumbered `d<day>-s<n>`. Copy is matched to days,
/// stops, places and lists by the plan's ids, and each stop's walk from the one before is measured with `walkTimes`.
public struct GuideAssembler: Sendable {
    public let walkTimes: any WalkTimes

    public init(walkTimes: any WalkTimes = StraightLineWalkTimes()) {
        self.walkTimes = walkTimes
    }

    /// Builds a draft guide version 1. Copy problems are returned, not thrown: the guide is still built, with empty
    /// text where copy is missing.
    ///
    /// `weather` is the expected weather keyed by date. A day with no entry gets no weather, and the default leaves
    /// every day without weather.
    public func assemble(
        id: String,
        facts: TripFacts,
        draft: PlanDraft,
        copy: GuideCopy,
        weather: [LocalDate: DayOutlook] = [:]
    ) -> AssemblyResult {
        var problems: [AssemblyProblem] = []
        let matched = Self.matchCopy(draft: draft, copy: copy, places: facts.places, problems: &problems)
        let places = Self.placesWithCopy(facts.places, referenced: matched.placeIds, copy: matched.places)
        let built = buildDays(draft: draft, matched: matched, places: places, weather: weather)
        let lists = draft.lists.map { draftList -> PlaceList in
            let text = matched.lists[draftList.key]
            return PlaceList(
                title: text?.title ?? "",
                caption: text?.caption ?? "",
                placeIds: draftList.placeIds,
                key: draftList.key
            )
        }
        let guide = Guide(
            id: id,
            version: 1,
            status: .draft,
            trip: facts.trip,
            bookings: facts.bookings,
            stay: facts.stay,
            places: places,
            days: built.days,
            lists: lists,
            tasting: copy.tasting,
            practical: facts.practical,
            sources: facts.sources,
            hero: copy.hero,
            notes: copy.notes,
            openQuestions: draft.openQuestions
        )
        return AssemblyResult(guide: guide, problems: problems, stopIds: built.stopIds)
    }
}
