/// A check's result, with the start time it sorts by inside its day (-1 for whole-day findings).
struct Finding: Sendable {
    let issue: PlanIssue
    let sortMinutes: Int
}

extension Finding {
    init(_ severity: IssueSeverity, _ kind: IssueKind, date: LocalDate, stop: Stop? = nil, message: String) {
        self.issue = PlanIssue(severity: severity, kind: kind, date: date, stopId: stop?.id, message: message)
        self.sortMinutes = stop?.start.minutesSinceMidnight ?? -1
    }
}
