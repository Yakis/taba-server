/// The pick lists the guide shows beside the days. The raw value is the key the planner and the writer use.
public enum ListKey: String, CaseIterable, Hashable, Sendable, Codable {
    case eat
    case drink
    case photos
    case groceries
}
