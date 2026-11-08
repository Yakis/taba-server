/// Practical notes for the whole trip, written for the guide.
public struct GuideNotes: Hashable, Sendable, Codable {
    public let weather: String
    public let light: String
    public let backupPlan: String
    /// A short, kind set of rules for the trip, in the guide's voice.
    public let rules: String

    public init(weather: String, light: String, backupPlan: String, rules: String) {
        self.weather = weather
        self.light = light
        self.backupPlan = backupPlan
        self.rules = rules
    }
}
