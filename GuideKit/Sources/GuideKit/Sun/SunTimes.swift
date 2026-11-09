import Foundation

/// Sunrise, sunset and the end of civil twilight (the evening blue hour) at one place on one date, in local time.
/// A time is nil when that event does not happen that day, as in polar night or midnight sun.
public struct SunTimes: Hashable, Sendable, Codable {
    public let sunrise: LocalTime?
    public let sunset: LocalTime?
    public let blueHourEnds: LocalTime?

    public init(sunrise: LocalTime?, sunset: LocalTime?, blueHourEnds: LocalTime?) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.blueHourEnds = blueHourEnds
    }

    /// NOAA-method sun times for `date` at `coordinate`, in `timeZoneId` with daylight saving applied.
    /// Returns nil when the time zone identifier is unknown.
    public static func compute(date: LocalDate, at coordinate: Coordinate, timeZoneId: String) -> SunTimes? {
        guard let zone = TimeZone(identifier: timeZoneId) else { return nil }
        func localTime(zenith: Double, rising: Bool) -> LocalTime? {
            guard let utc = SunEvents.utcMinutes(
                on: date,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                zenith: zenith,
                rising: rising
            ) else {
                return nil
            }
            return SunEvents.localTime(utcMinutes: utc, on: date, in: zone)
        }
        return SunTimes(
            sunrise: localTime(zenith: SunEvents.officialZenith, rising: true),
            sunset: localTime(zenith: SunEvents.officialZenith, rising: false),
            blueHourEnds: localTime(zenith: SunEvents.civilZenith, rising: false)
        )
    }
}
