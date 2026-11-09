import Foundation

/// Sun position formulas from the NOAA solar calculator, which follow Meeus. Used for sunrise, sunset and twilight.
enum SolarPosition {
    /// The Julian day number at 00:00 UT on `date`.
    static func julianDayAtUTCMidnight(_ date: LocalDate) -> Double {
        var year = Double(date.year)
        var month = Double(date.month)
        if month <= 2 {
            year -= 1
            month += 12
        }
        let century = (year / 100).rounded(.down)
        let gregorianCorrection = 2 - century + (century / 4).rounded(.down)
        return (365.25 * (year + 4716)).rounded(.down)
            + (30.6001 * (month + 1)).rounded(.down)
            + Double(date.day) + gregorianCorrection - 1524.5
    }

    /// The sun's declination (radians) and the equation of time (minutes) at a Julian day.
    static func declinationAndEquationOfTime(julianDay: Double) -> (declination: Double, equationOfTime: Double) {
        let centuries = (julianDay - 2_451_545) / 36_525
        let meanLongitude = normalisedDegrees(280.46646 + centuries * (36_000.76983 + centuries * 0.0003032))
        let meanAnomaly = normalisedDegrees(357.52911 + centuries * (35_999.05029 - 0.0001537 * centuries))
        let eccentricity = 0.016708634 - centuries * (0.000042037 + 0.0000001267 * centuries)
        let anomaly = radians(meanAnomaly)
        let centre = sin(anomaly) * (1.914602 - centuries * (0.004817 + 0.000014 * centuries))
            + sin(2 * anomaly) * (0.019993 - 0.000101 * centuries)
            + sin(3 * anomaly) * 0.000289
        let trueLongitude = meanLongitude + centre
        let omega = radians(125.04 - 1934.136 * centuries)
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(omega)
        let obliquityPolynomial = 21.448 - centuries * (46.815 + centuries * (0.00059 - centuries * 0.001813))
        let meanObliquity = 23 + (26 + obliquityPolynomial / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(omega)
        let declination = asin(sin(radians(obliquity)) * sin(radians(apparentLongitude)))

        let tanHalf = tan(radians(obliquity) / 2)
        let yValue = tanHalf * tanHalf
        let doubleLongitude = 2 * radians(meanLongitude)
        let equation = yValue * sin(doubleLongitude)
            - 2 * eccentricity * sin(anomaly)
            + 4 * eccentricity * yValue * sin(anomaly) * cos(doubleLongitude)
            - 0.5 * yValue * yValue * sin(2 * doubleLongitude)
            - 1.25 * eccentricity * eccentricity * sin(2 * anomaly)
        return (declination, 4 * degrees(equation))
    }

    static func radians(_ value: Double) -> Double {
        value * .pi / 180
    }

    static func degrees(_ value: Double) -> Double {
        value * 180 / .pi
    }

    private static func normalisedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}
