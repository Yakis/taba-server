/// How serious a plan issue is. Errors must be fixed, warnings should be, and info is for the traveller's awareness.
public enum IssueSeverity: String, CaseIterable, Hashable, Sendable, Codable {
    case error
    case warning
    case info
}
