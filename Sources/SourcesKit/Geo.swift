import Foundation
import GuideKit

/// Great-circle distance.
public enum Geo {
    public static func metres(from first: Coordinate, to second: Coordinate) -> Double {
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
