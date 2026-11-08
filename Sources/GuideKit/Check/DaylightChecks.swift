extension PlanChecker {
    /// Outdoor sights that start at or after sunset, or less than 30 minutes before it.
    func daylightFindings(_ context: CheckContext) -> [Finding] {
        var findings: [Finding] = []
        for day in context.guide.days {
            let sun = context.sunTimes(on: day.date)
            var reportedMissingSunset = false
            for stop in day.stops where stop.kind == .sight {
                guard let place = context.place(stop.placeId), !place.indoor, !place.isDaylightExempt else {
                    continue
                }
                guard let sunset = sun?.sunset else {
                    if !reportedMissingSunset {
                        let message = "There is no sunset on \(day.date), so daylight is not checked."
                        findings.append(Finding(.info, .noDaylightData, date: day.date, message: message))
                        reportedMissingSunset = true
                    }
                    continue
                }
                let start = stop.start.minutesSinceMidnight
                let sunsetMinutes = sunset.minutesSinceMidnight
                if start >= sunsetMinutes {
                    let message = "\(place.name) starts at \(Clock.text(start)), "
                        + "after the \(Clock.text(sunsetMinutes)) sunset."
                    findings.append(Finding(.error, .afterSunset, date: day.date, stop: stop, message: message))
                } else if sunsetMinutes - start < 30 {
                    let message = "\(place.name) starts at \(Clock.text(start)), only \(sunsetMinutes - start) minutes "
                        + "before the \(Clock.text(sunsetMinutes)) sunset."
                    findings.append(Finding(.warning, .nearSunset, date: day.date, stop: stop, message: message))
                }
            }
        }
        return findings
    }
}
