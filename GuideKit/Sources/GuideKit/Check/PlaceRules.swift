extension Place {
    /// Streets, neighbourhoods and viewpoints, and landmarks that are not indoors. Opening hours matter less here.
    var isOutdoorPublicSpace: Bool {
        switch kind {
        case .street, .neighbourhood, .viewpoint:
            return true
        case .landmark:
            return !indoor
        default:
            return false
        }
    }

    /// Markets, and landmarks named for lights or Christmas, are meant for after dark, so daylight checks skip them.
    var isDaylightExempt: Bool {
        if kind == .market {
            return true
        }
        let lowered = name.lowercased()
        return kind == .landmark && (lowered.contains("light") || lowered.contains("christmas"))
    }
}

extension Pace {
    /// The walking minutes a full day is planned around. The walking check warns above 1.2 times this.
    public var walkingLimitMinutes: Int {
        switch self {
        case .relaxed:
            return 100
        case .unhurried:
            return 130
        case .packed:
            return 180
        }
    }

    /// The main stops (sights and drinks) a full day is planned around, from the pace table in plan.md rule 10. Packed
    /// has no upper limit.
    public var mainStopRange: ClosedRange<Int> {
        switch self {
        case .relaxed: 3...4
        case .unhurried: 4...5
        case .packed: 6...Int.max
        }
    }

    /// The earliest start of a full day's first main stop, or nil when there is no limit.
    public var firstMainStopNotBefore: LocalTime? {
        switch self {
        case .relaxed: LocalTime(hour: 9, minute: 30)
        case .unhurried: LocalTime(hour: 9, minute: 0)
        case .packed: nil
        }
    }
}
