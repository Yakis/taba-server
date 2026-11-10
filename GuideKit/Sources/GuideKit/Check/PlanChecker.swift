/// Checks a guide's plan against opening hours, walking times, daylight, meals, travel, the stay, pace and
/// repeated places.
///
/// The rules and numbers match the planning prompt, so the AI and this checker agree.
public struct PlanChecker: Sendable {
    public let walkTimes: any WalkTimes

    public init(walkTimes: any WalkTimes = StraightLineWalkTimes()) {
        self.walkTimes = walkTimes
    }

    /// Every issue found, sorted by date, then stop start, then kind.
    public func check(_ guide: Guide) -> [PlanIssue] {
        let context = CheckContext(guide: guide, walkTimes: walkTimes)
        let findings = hoursFindings(context)
            + timingFindings(context)
            + mealFindings(context)
            + daylightFindings(context)
            + transitFindings(context)
            + stayFindings(context)
            + paceFindings(context)
            + repeatFindings(context)
        return findings.sorted(by: Self.isOrderedBefore).map(\.issue)
    }

    private static func isOrderedBefore(_ lhs: Finding, _ rhs: Finding) -> Bool {
        if lhs.issue.date != rhs.issue.date {
            return lhs.issue.date < rhs.issue.date
        }
        if lhs.sortMinutes != rhs.sortMinutes {
            return lhs.sortMinutes < rhs.sortMinutes
        }
        if lhs.issue.kind != rhs.issue.kind {
            return lhs.issue.kind.rawValue < rhs.issue.kind.rawValue
        }
        return lhs.issue.message < rhs.issue.message
    }
}
