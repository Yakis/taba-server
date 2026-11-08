import Foundation
import GuideKit

/// Name comparison and distance, for matching a Foursquare hit to a fixture place.
public enum NameMatch {
    /// Lowercase, accents removed, "&" read as "and", punctuation removed, and a leading "the" dropped.
    public static func normalised(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let spelled = folded.replacingOccurrences(of: "&", with: " and ")
        let cleaned = String(spelled.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var words = cleaned.split(separator: " ").map(String.init)
        if words.first == "the" {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// True when the normalised names are equal, or one contains the other and the shorter is 4 or more characters.
    public static func matches(_ fixtureName: String, _ hitName: String) -> Bool {
        let first = normalised(fixtureName)
        let second = normalised(hitName)
        if first == second {
            return true
        }
        let shorter = first.count <= second.count ? first : second
        let longer = first.count <= second.count ? second : first
        return shorter.count >= 4 && longer.contains(shorter)
    }
}

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
