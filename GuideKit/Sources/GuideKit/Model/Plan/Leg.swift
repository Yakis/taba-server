/// The journey from the previous stop to this one. Computed after planning.
public struct Leg: Hashable, Sendable, Codable {
    public let mode: LegMode
    public let minutes: Int
    public let metres: Int

    public init(mode: LegMode, minutes: Int, metres: Int) {
        self.mode = mode
        self.minutes = minutes
        self.metres = metres
    }
}
