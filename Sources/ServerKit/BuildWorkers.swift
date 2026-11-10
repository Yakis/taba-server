import Foundation

/// How many stage jobs the server runs at once. Each trip still runs one stage at a time.
public enum BuildWorkers {
    public static let defaultCount = 3
    public static let allowed = 1...4

    /// The value of `TABA_WORKERS`. A missing value, or one that is not a whole number from 1 to 4, gives the default.
    public static func count(from value: String?) -> Int {
        guard let value, let count = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              allowed.contains(count) else {
            return defaultCount
        }
        return count
    }
}
