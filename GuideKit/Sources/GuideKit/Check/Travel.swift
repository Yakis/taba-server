import Foundation

/// How a traveller gets between two points: on foot up to `longestWalkMinutes`, otherwise a bus or taxi ride.
public enum Travel {
    /// The longest walk the guide plans. A longer journey becomes a ride.
    public static let longestWalkMinutes = 30

    /// The leg between two points. `metres` is the straight-line distance, rounded, as legs record it today.
    public static func leg(from origin: Coordinate, to destination: Coordinate, walkTimes: any WalkTimes) -> Leg {
        leg(
            walkMinutes: walkTimes.minutes(from: origin, to: destination),
            metres: metres(from: origin, to: destination)
        )
    }

    /// The same rule from a walk estimate and a straight-line distance in metres.
    public static func leg(walkMinutes: Int, metres: Double) -> Leg {
        let rounded = Int(metres.rounded())
        if walkMinutes <= longestWalkMinutes {
            return Leg(mode: .walk, minutes: walkMinutes, metres: rounded)
        }
        return Leg(mode: .transit, minutes: rideMinutes(metres: metres), metres: rounded)
    }

    /// Minutes by bus or taxi: 10 minutes to wait or hail, then the distance times 1.3 for roads at 500 metres
    /// a minute (30 km/h), rounded up.
    public static func rideMinutes(metres: Double) -> Int {
        let roadMetres = max(0, metres) * 1.3
        return 10 + Int((roadMetres / 500).rounded(.up))
    }

    /// The straight-line distance in metres between two coordinates.
    public static func metres(from origin: Coordinate, to destination: Coordinate) -> Double {
        StraightLineWalkTimes.haversineMetres(origin, destination)
    }
}
