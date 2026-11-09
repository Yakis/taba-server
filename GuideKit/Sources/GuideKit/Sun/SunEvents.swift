import Foundation

/// Finds when the sun crosses a given altitude, and converts the result to local time.
enum SunEvents {
    /// Sunrise and sunset use -0.833 degrees of altitude, which allows for refraction and the sun's radius.
    static let officialZenith = 90.833
    /// Civil twilight ends when the sun is 6 degrees below the horizon.
    static let civilZenith = 96.0

    /// Minutes after 00:00 UT on `date` when the sun reaches `zenith`, or nil when it never does that day.
    static func utcMinutes(
        on date: LocalDate,
        latitude: Double,
        longitude: Double,
        zenith: Double,
        rising: Bool
    ) -> Double? {
        let midnight = SolarPosition.julianDayAtUTCMidnight(date)
        let latitudeRadians = SolarPosition.radians(latitude)
        var minutes = rising ? 360.0 : 1080.0
        for _ in 0..<10 {
            let position = SolarPosition.declinationAndEquationOfTime(julianDay: midnight + minutes / 1440)
            let declination = position.declination
            let cosineOfHalfDay = cos(SolarPosition.radians(zenith)) / (cos(latitudeRadians) * cos(declination))
                - tan(latitudeRadians) * tan(declination)
            guard (-1.0...1.0).contains(cosineOfHalfDay) else { return nil }
            let halfDay = SolarPosition.degrees(acos(cosineOfHalfDay))
            let noon = 720 - 4 * longitude - position.equationOfTime
            minutes = rising ? noon - 4 * halfDay : noon + 4 * halfDay
        }
        return minutes
    }

    /// Converts UTC minutes after midnight on `date` to local time in `zone`, using that moment's offset.
    static func localTime(utcMinutes: Double, on date: LocalDate, in zone: TimeZone) -> LocalTime? {
        let midnight = SolarPosition.julianDayAtUTCMidnight(date)
        let instant = Date(timeIntervalSince1970: (midnight - 2_440_587.5) * 86_400 + utcMinutes * 60)
        let offsetMinutes = Double(zone.secondsFromGMT(for: instant)) / 60
        let localMinutes = Int((utcMinutes + offsetMinutes).rounded())
        let dayMinutes = ((localMinutes % 1440) + 1440) % 1440
        return LocalTime(minutesSinceMidnight: dayMinutes)
    }
}
