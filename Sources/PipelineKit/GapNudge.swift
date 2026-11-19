import GuideKit

/// A deterministic fix for gaps that are a few minutes too short, so the AI is not asked to repair them.
///
/// The checker reports a `tightGap` (the gap is shorter than the walk or ride) or a `shortGap` (shorter than the
/// buffer `PlanChecker.minimumBuffer` leaves) on the later stop of a pair. For each such pair the nudge first
/// shortens the earlier stop, and when it cannot, starts the later stop a little later. It changes nothing else:
/// fixed stops, journeys, logistics and booked places never move. When anything is unclear it returns nil and the
/// repair runs as before.
public struct GapNudge: Sendable {
    /// The nudged plan and one plain sentence for each change.
    public struct Outcome: Sendable, Equatable {
        public let draft: PlanDraft
        public let changes: [String]
    }

    /// A shortened stop keeps at least this share of its minutes, and at least `minimumMinutes`.
    static let keptShare = 0.75
    static let minimumMinutes = 20

    private let facts: TripFacts
    private let walkTimes: any WalkTimes

    public init(facts: TripFacts, walkTimes: any WalkTimes) {
        self.facts = facts
        self.walkTimes = walkTimes
    }

    /// True when every issue that is not `.info` is a gap issue about a named stop. Draft problems that use
    /// `.tightGap` for the plan's structure carry no stop id, so they never qualify.
    public static func isGapOnly(_ issues: [PlanIssue]) -> Bool {
        let blocking = issues.filter { $0.severity != .info }
        return !blocking.isEmpty && blocking.allSatisfy {
            ($0.kind == .tightGap || $0.kind == .shortGap) && $0.stopId != nil
        }
    }

    /// The plan with every gap issue fixed, or nil when any one of them cannot be fixed safely.
    public func apply(to draft: PlanDraft, issues: [PlanIssue]) -> Outcome? {
        guard Self.isGapOnly(issues) else { return nil }
        var days = draft.days
        var changes: [String] = []
        var handled = Set<String>()
        for issue in issues where issue.severity != .info {
            guard let id = issue.stopId, handled.insert(id).inserted else { continue }
            guard let index = days.firstIndex(where: { $0.date == issue.date && $0.stops.contains { $0.id == id } }),
                  let fix = fix(stopId: id, in: days[index].stops, date: issue.date) else { return nil }
            days[index] = PlanDraftDay(date: days[index].date, theme: days[index].theme, stops: fix.stops)
            changes += fix.changes
        }
        guard !changes.isEmpty else { return nil }
        return Outcome(
            draft: PlanDraft(days: days, lists: draft.lists, skippedMeals: draft.skippedMeals,
                             openQuestions: draft.openQuestions, changes: draft.changes),
            changes: changes)
    }

    // The earlier stop of the pair is the one before `stopId` in time order, as the assembler sorts a day. A fix
    // with no changes means the pair is already fine, for example after an earlier fix moved a stop.
    private func fix(stopId: String, in stops: [PlanDraftStop],
                     date: LocalDate) -> (stops: [PlanDraftStop], changes: [String])? {
        let order = stops.indices.sorted { lhs, rhs in
            stops[lhs].start != stops[rhs].start ? stops[lhs].start < stops[rhs].start : lhs < rhs
        }
        guard let position = order.firstIndex(where: { stops[$0].id == stopId }), position > 0 else { return nil }
        let earlierIndex = order[position - 1]
        let laterIndex = order[position]
        let earlier = stops[earlierIndex]
        let later = stops[laterIndex]
        guard let leg = leg(earlier.placeId, later.placeId) else { return nil }
        let gap = later.start.minutesSinceMidnight - (earlier.start.minutesSinceMidnight + earlier.minutes)
        guard gap >= 0 else { return nil }
        let missing = PlanChecker.requiredGap(legMinutes: leg.minutes) - gap
        guard missing > 0 else { return (stops, []) }
        var result = stops
        if canChange(earlier, on: date), earlier.minutes - missing >= Self.floor(for: earlier.minutes) {
            result[earlierIndex] = copy(earlier, start: earlier.start, minutes: earlier.minutes - missing)
            let sentence = "Shortened \(earlier.id) by \(missing) minutes, from \(earlier.minutes) to "
                + "\(earlier.minutes - missing)."
            return (result, [sentence])
        }
        guard canChange(later, on: date), later.flexible,
              let start = later.start.adding(minutes: missing),
              start.minutesSinceMidnight + later.minutes < 24 * 60,
              roomAfter(laterIndex, order: order, position: position, in: stops, newStart: start) else { return nil }
        result[laterIndex] = copy(later, start: start, minutes: later.minutes)
        return (result, ["Started \(later.id) \(missing) minutes later, at \(start)."])
    }

    /// True when the stop after the moved one still has the gap the checker wants, or no overlap when no leg is known.
    private func roomAfter(_ index: Int, order: [Int], position: Int, in stops: [PlanDraftStop],
                           newStart: LocalTime) -> Bool {
        guard position + 1 < order.count else { return true }
        let moved = stops[index]
        let next = stops[order[position + 1]]
        let gap = next.start.minutesSinceMidnight - (newStart.minutesSinceMidnight + moved.minutes)
        let needed = leg(moved.placeId, next.placeId).map { PlanChecker.requiredGap(legMinutes: $0.minutes) } ?? 0
        return gap >= needed
    }

    /// A stop that is neither a journey nor logistics, and whose place has no ticket booked for the day.
    private func canChange(_ stop: PlanDraftStop, on date: LocalDate) -> Bool {
        guard stop.kind != .travel, stop.kind != .logistics else { return false }
        guard let placeId = stop.placeId else { return true }
        return !facts.bookings.contains { booking in
            booking.kind == .ticket && booking.departs.date == date
                && (booking.fromPlaceId == placeId || booking.toPlaceId == placeId)
        }
    }

    private static func floor(for minutes: Int) -> Int {
        max(minimumMinutes, Int((Double(minutes) * keptShare).rounded(.up)))
    }

    private func leg(_ first: String?, _ second: String?) -> Leg? {
        guard let first = first.flatMap({ facts.places[$0] }), let second = second.flatMap({ facts.places[$0] }) else {
            return nil
        }
        return Travel.leg(from: first.location.coordinate, to: second.location.coordinate, walkTimes: walkTimes)
    }

    private func copy(_ stop: PlanDraftStop, start: LocalTime, minutes: Int) -> PlanDraftStop {
        PlanDraftStop(id: stop.id, placeId: stop.placeId, kind: stop.kind, mealSlot: stop.mealSlot, start: start,
                      minutes: minutes, flexible: stop.flexible, alternative: stop.alternative, reason: stop.reason,
                      findingIds: stop.findingIds)
    }
}

/// What the plan check needs to assemble and check a draft.
struct PlanCheckScope {
    let id: String
    let facts: TripFacts
    let served: [String: [String]]
}

extension GuidePipeline {
    /// The checker's issues for a draft, with stop ids mapped back to the draft's own ids.
    func checkAssembled(_ draft: PlanDraft, _ scope: PlanCheckScope) -> [PlanIssue] {
        let assembled = GuideAssembler(walkTimes: walkTimes).assemble(
            id: scope.id, facts: scope.facts, draft: draft, copy: emptyCopy, servedInterests: scope.served)
        let reverse = Dictionary(assembled.stopIds.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        return PlanChecker(walkTimes: walkTimes).check(assembled.guide).map { issue in
            PlanIssue(severity: issue.severity, kind: issue.kind, date: issue.date,
                      stopId: issue.stopId.map { reverse[$0] ?? $0 }, message: issue.message)
        }
    }

    /// The nudged draft, its issues and what changed, when the nudge fixes every blocking issue and the checker then
    /// finds nothing but info. Otherwise nil, and the repair runs as before.
    func nudge(_ draft: PlanDraft, issues: [PlanIssue], _ scope: PlanCheckScope) -> NudgedPlan? {
        guard let outcome = GapNudge(facts: scope.facts, walkTimes: walkTimes).apply(to: draft, issues: issues) else {
            return nil
        }
        let rechecked = checkAssembled(outcome.draft, scope)
        guard !rechecked.contains(where: { $0.severity != .info }) else { return nil }
        return NudgedPlan(draft: outcome.draft, issues: rechecked, changes: outcome.changes)
    }
}

struct NudgedPlan {
    let draft: PlanDraft
    let issues: [PlanIssue]
    let changes: [String]
}
