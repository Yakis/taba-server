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
    var walkingLimitMinutes: Int {
        switch self {
        case .relaxed:
            return 100
        case .unhurried:
            return 130
        case .packed:
            return 180
        }
    }
}
