/// The copy matched to the plan's ids. Each map holds only ids the plan uses.
struct MatchedCopy {
    let days: [LocalDate: DayCopy]
    let stops: [String: StopCopy]
    let places: [String: PlaceCopy]
    let lists: [ListKey: GuideCopyList]
    /// Every place the plan uses, in first-seen order.
    let placeIds: [String]
}

extension GuideAssembler {
    /// Placeholders for copy that is missing. The matching problem is reported, so these never reach a checked guide.
    static let emptyDayCopy = DayCopy(title: "", summary: "")
    static let emptyStopCopy = StopCopy(title: "", body: "", actionLabel: nil)

    /// Matches the copy to the plan's days, stops, places and lists by id, and records every mismatch. A place with
    /// a kind that needs no copy (see `PlaceKind.needsCopy`) is not reported when its copy is missing.
    static func matchCopy(
        draft: PlanDraft,
        copy: GuideCopy,
        places: [String: Place],
        problems: inout [AssemblyProblem]
    ) -> MatchedCopy {
        let placeIds = referencedPlaceIds(draft)
        let placesNeedingCopy = placeIds.filter { places[$0]?.kind.needsCopy ?? true }
        let days = index(
            copy.days.map { (key: $0.date, value: DayCopy(title: $0.title, summary: $0.summary)) },
            expected: draft.days.map(\.date),
            target: CopyTarget.day,
            problems: &problems
        )
        let stops = index(
            copy.stops.map { stop in
                (key: stop.id, value: StopCopy(title: stop.title, body: stop.body, actionLabel: stop.actionLabel))
            },
            expected: draft.days.flatMap { $0.stops.map(\.id) },
            target: CopyTarget.stop,
            problems: &problems
        )
        let placesWithoutNeed = placeIds.filter { !placesNeedingCopy.contains($0) }
        let places = index(
            copy.places.map { (key: $0.id, value: PlaceCopy(tag: $0.tag, blurb: $0.blurb)) },
            expected: placesNeedingCopy,
            optional: placesWithoutNeed,
            target: CopyTarget.place,
            problems: &problems
        )
        let lists = index(
            copy.lists.map { (key: $0.key, value: $0) },
            expected: draft.lists.map(\.key),
            target: CopyTarget.list,
            problems: &problems
        )
        return MatchedCopy(days: days, stops: stops, places: places, lists: lists, placeIds: placeIds)
    }

    /// Matches copy to the expected ids. Each expected id with no copy is missing. Copy for an optional id is kept
    /// when given, and is not a problem when absent. Copy for any other id is extra and dropped. Copy repeated for one
    /// id keeps its first entry.
    static func index<Key: Hashable, Value>(
        _ entries: [(key: Key, value: Value)],
        expected: [Key],
        optional: [Key] = [],
        target: (Key) -> CopyTarget,
        problems: inout [AssemblyProblem]
    ) -> [Key: Value] {
        let wanted = Set(expected).union(optional)
        var found: [Key: Value] = [:]
        for entry in entries {
            guard wanted.contains(entry.key) else {
                problems.append(.extraCopy(target(entry.key)))
                continue
            }
            guard found[entry.key] == nil else {
                problems.append(.duplicateCopy(target(entry.key)))
                continue
            }
            found[entry.key] = entry.value
        }
        var reported = Set<Key>()
        for key in expected where found[key] == nil && reported.insert(key).inserted {
            problems.append(.missingCopy(target(key)))
        }
        return found
    }

    /// Every place id the plan uses: its stops, their alternatives and its pick lists, in first-seen order.
    static func referencedPlaceIds(_ draft: PlanDraft) -> [String] {
        var ids: [String] = []
        for day in draft.days {
            for stop in day.stops {
                ids += [stop.placeId, stop.alternative?.placeId].compactMap { $0 }
            }
        }
        ids += draft.lists.flatMap(\.placeIds)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// The places with copy from the writer. A used place that needs copy and has none gets none, and the missing
    /// copy is reported. A used place that needs no copy keeps the copy it already has when the writer gives none.
    /// Places the plan does not use keep whatever copy they already have.
    static func placesWithCopy(
        _ places: [String: Place],
        referenced: [String],
        copy: [String: PlaceCopy]
    ) -> [String: Place] {
        var result = places
        for id in referenced {
            guard let place = places[id] else { continue }
            if let text = copy[id] {
                result[id] = place.withCopy(text)
            } else if place.kind.needsCopy {
                result[id] = place.withCopy(nil)
            }
        }
        return result
    }
}

extension Place {
    /// This place with its copy replaced.
    func withCopy(_ copy: PlaceCopy?) -> Place {
        Place(
            id: id,
            name: name,
            kind: kind,
            location: location,
            hours: hours,
            priceLevel: priceLevel,
            booking: booking,
            indoor: indoor,
            images: images,
            facts: facts,
            copy: copy,
            website: website,
            phone: phone,
            interests: interests
        )
    }

    /// This place with the interests it serves replaced.
    func withInterests(_ interests: [String]?) -> Place {
        Place(
            id: id,
            name: name,
            kind: kind,
            location: location,
            hours: hours,
            priceLevel: priceLevel,
            booking: booking,
            indoor: indoor,
            images: images,
            facts: facts,
            copy: copy,
            website: website,
            phone: phone,
            interests: interests
        )
    }
}
