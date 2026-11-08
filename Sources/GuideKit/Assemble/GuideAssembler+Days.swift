extension GuideAssembler {
    /// The plan's days in date order. Each day's stops are sorted by time and renumbered `d<day>-s<n>`, and each
    /// stop gets a walk leg from the stop before it when both have places. Also returns the plan-to-guide stop ids.
    func buildDays(
        draft: PlanDraft,
        matched: MatchedCopy,
        places: [String: Place]
    ) -> (days: [Day], stopIds: [String: String]) {
        var days: [Day] = []
        var stopIds: [String: String] = [:]
        for (dayIndex, draftDay) in draft.days.sorted(by: { $0.date < $1.date }).enumerated() {
            var stops: [Stop] = []
            var previousPlace: Place?
            for (position, draftStop) in Self.timeOrder(draftDay.stops).enumerated() {
                let newId = "d\(dayIndex + 1)-s\(position + 1)"
                stopIds[draftStop.id] = newId
                let place = draftStop.placeId.flatMap { places[$0] }
                stops.append(Stop(
                    id: newId,
                    kind: draftStop.kind,
                    mealSlot: draftStop.mealSlot,
                    placeId: draftStop.placeId,
                    start: draftStop.start,
                    minutes: draftStop.minutes,
                    flexible: draftStop.flexible,
                    alternative: draftStop.alternative,
                    copy: matched.stops[draftStop.id] ?? Self.emptyStopCopy,
                    legFromPrevious: leg(from: previousPlace, to: place)
                ))
                previousPlace = place
            }
            let copy = matched.days[draftDay.date] ?? Self.emptyDayCopy
            days.append(Day(date: draftDay.date, copy: copy, stops: stops))
        }
        return (days, stopIds)
    }

    /// The stops in time order. Stops that start together keep the order the plan gave them.
    static func timeOrder(_ stops: [PlanDraftStop]) -> [PlanDraftStop] {
        stops.enumerated().sorted { lhs, rhs in
            if lhs.element.start != rhs.element.start {
                return lhs.element.start < rhs.element.start
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The walk from one place to the next, or nil when either stop has no place.
    private func leg(from previous: Place?, to current: Place?) -> Leg? {
        guard let previous, let current else { return nil }
        let origin = previous.location.coordinate
        let destination = current.location.coordinate
        let metres = StraightLineWalkTimes.haversineMetres(origin, destination)
        return Leg(
            mode: .walk,
            minutes: walkTimes.minutes(from: origin, to: destination),
            metres: Int(metres.rounded())
        )
    }
}
