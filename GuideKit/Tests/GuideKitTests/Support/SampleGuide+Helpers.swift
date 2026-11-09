import GuideKit

// Fixture helpers. These trap on bad input, which is fine because the inputs are literals.
extension SampleGuide {
    static func date(_ text: String) -> LocalDate {
        guard let value = LocalDate(text) else { preconditionFailure("Bad fixture date \(text)") }
        return value
    }

    static func time(_ text: String) -> LocalTime {
        guard let value = LocalTime(text) else { preconditionFailure("Bad fixture time \(text)") }
        return value
    }

    static func dateTime(_ text: String) -> LocalDateTime {
        guard let value = LocalDateTime(text) else { preconditionFailure("Bad fixture date-time \(text)") }
        return value
    }

    static func coordinate(_ latitude: Double, _ longitude: Double) -> Coordinate {
        guard let value = Coordinate(latitude: latitude, longitude: longitude) else {
            preconditionFailure("Bad fixture coordinate \(latitude), \(longitude)")
        }
        return value
    }
}
