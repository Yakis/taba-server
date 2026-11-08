import Foundation

/// Estimates walking minutes between two coordinates. The server can later swap in Apple Maps times.
public protocol WalkTimes: Sendable {
    func minutes(from origin: Coordinate, to destination: Coordinate) -> Int
}

/// Straight-line distance (haversine) times 1.3 for detours, walked at 80 metres a minute, rounded up.
/// Never less than 1 minute.
public struct StraightLineWalkTimes: WalkTimes {
    public init() {}

    public func minutes(from origin: Coordinate, to destination: Coordinate) -> Int {
        let metres = Self.haversineMetres(origin, destination) * 1.3
        return max(1, Int((metres / 80).rounded(.up)))
    }

    static func haversineMetres(_ first: Coordinate, _ second: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let firstLatitude = first.latitude * .pi / 180
        let secondLatitude = second.latitude * .pi / 180
        let deltaLatitude = (second.latitude - first.latitude) * .pi / 180
        let deltaLongitude = (second.longitude - first.longitude) * .pi / 180
        let chord = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(firstLatitude) * cos(secondLatitude) * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        return 2 * earthRadius * asin(min(1, sqrt(chord)))
    }
}
