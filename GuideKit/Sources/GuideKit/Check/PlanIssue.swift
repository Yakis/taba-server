/// One finding from `PlanChecker`. It is sent to the AI as JSON, so every field is plain data.
public struct PlanIssue: Hashable, Sendable, Codable {
    public let severity: IssueSeverity
    public let kind: IssueKind
    public let date: LocalDate
    /// The stop the issue is about, or nil when it is about the whole day.
    public let stopId: String?
    /// One plain sentence with the measured numbers.
    public let message: String

    public init(severity: IssueSeverity, kind: IssueKind, date: LocalDate, stopId: String?, message: String) {
        self.severity = severity
        self.kind = kind
        self.date = date
        self.stopId = stopId
        self.message = message
    }
}
