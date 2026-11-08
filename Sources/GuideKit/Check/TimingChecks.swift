extension PlanChecker {
    /// Overlaps, and gaps too short for the walk or for comfort, between consecutive stops in each day.
    func timingFindings(_ context: CheckContext) -> [Finding] {
        var findings: [Finding] = []
        for day in context.guide.days {
            let stops = day.stops.sorted { $0.start < $1.start }
            for (previous, next) in zip(stops, stops.dropFirst()) {
                findings += pairFindings(previous, next, date: day.date, context)
            }
        }
        return findings
    }

    private func pairFindings(_ previous: Stop, _ next: Stop, date: LocalDate, _ context: CheckContext) -> [Finding] {
        let previousEnd = previous.start.minutesSinceMidnight + previous.minutes
        let nextStart = next.start.minutesSinceMidnight
        if nextStart < previousEnd {
            let message = "\(context.label(next)) starts at \(Clock.text(nextStart)), "
                + "before \(context.label(previous)) ends at \(Clock.text(previousEnd))."
            return [Finding(.error, .overlap, date: date, stop: next, message: message)]
        }
        let gap = nextStart - previousEnd
        guard let walk = context.stopWalkMinutes(previous.placeId, next.placeId) else {
            return []
        }
        let names = "\(context.label(previous)) and \(context.label(next))"
        if gap < walk {
            let message = "Only \(gap) minutes between \(names), but the walk takes about \(walk) minutes."
            return [Finding(.error, .tightGap, date: date, stop: next, message: message)]
        }
        // Same area (a walk of 5 minutes or less): leave 5 minutes. Between areas: leave at least 10.
        let threshold = walk <= 5 ? 5 : 10
        if gap < threshold {
            let message = "Only \(gap) minutes between \(names); leave at least \(threshold)."
            return [Finding(.warning, .shortGap, date: date, stop: next, message: message)]
        }
        return []
    }
}
