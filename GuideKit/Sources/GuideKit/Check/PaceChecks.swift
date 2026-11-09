extension PlanChecker {
    /// A day's walking, summed over the walk legs between consecutive stops that have places, against 1.2 times the
    /// pace limit. Bus and taxi rides are not walking, so they are left out.
    func paceFindings(_ context: CheckContext) -> [Finding] {
        let pace = context.guide.trip.pace
        let limit = pace.walkingLimitMinutes
        var findings: [Finding] = []
        for day in context.guide.days {
            let placed = day.stops.sorted { $0.start < $1.start }.filter { $0.placeId != nil }
            let total = zip(placed, placed.dropFirst()).reduce(0) { sum, pair in
                guard let leg = context.stopLeg(pair.0.placeId, pair.1.placeId), leg.mode == .walk else {
                    return sum
                }
                return sum + leg.minutes
            }
            if total * 5 > limit * 6 {
                let message = "Walking on \(day.date) adds up to \(total) minutes, "
                    + "more than 1.2 times the \(limit)-minute \(pace.rawValue) limit."
                findings.append(Finding(.warning, .walkingOverPace, date: day.date, message: message))
            }
        }
        return findings
    }
}
