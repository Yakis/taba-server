/// Parsing and formatting for the zero-padded, fixed-width numbers used in "YYYY-MM-DD" and "HH:MM".
enum FixedWidthNumber {
    /// Parses `text` only when it is exactly `width` ASCII digits, so "+1", " 1" and "1" are all rejected.
    static func parse(_ text: Substring, width: Int) -> Int? {
        guard text.utf8.count == width, text.utf8.allSatisfy({ (48...57).contains($0) }) else {
            return nil
        }
        return Int(text)
    }

    /// Formats a non-negative value with leading zeros up to `width` digits.
    static func format(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
