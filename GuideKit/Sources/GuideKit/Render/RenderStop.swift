import Foundation

/// One stop on a day's timeline: the walk row before it (when one is worth showing) and the stop card. Follows the
/// app's `StopRow`: the place's name shows only when it adds to the title, and the rain alternative is one line.
enum RenderStop {
    /// The timeline rows for one stop: its leg from the previous stop when there is one, then the stop card.
    static func rows(_ stop: Stop, previousPlaceId: String?, date: LocalDate, guide: Guide) -> [String] {
        var rows: [String] = []
        if let leg = RenderLeg.text(stop.legFromPrevious, previousPlaceId: previousPlaceId, placeId: stop.placeId) {
            rows.append(legRow(leg))
        }
        rows.append(stopRow(stop, date: date, guide: guide))
        return rows
    }

    private static func legRow(_ text: String) -> String {
        [
            "<li class=\"row leg\">",
            "<span class=\"time\"></span>",
            "<span class=\"rail\"></span>",
            "<p class=\"leg-text\">\(HTML.escape(text))</p>",
            "</li>"
        ].joined(separator: "\n")
    }

    private static func stopRow(_ stop: Stop, date: LocalDate, guide: Guide) -> String {
        let place = stop.placeId.flatMap { guide.places[$0] }
        let kind = StopKindStyle.forStop(stop)
        let hours = place.flatMap { RenderHours.atStop($0.hours, kind: $0.kind, on: date, at: stop.start) }
        let classes = ["row", "stop", kind.cssClass].joined(separator: " ")
        return [
            "<li class=\"\(classes)\" id=\"\(HTML.stopAnchor(stop.id))\">",
            "<span class=\"time\">\(RenderText.time(stop.start))</span>",
            "<span class=\"rail\"><span class=\"dot\"></span></span>",
            card(stop, place: place, kind: kind, hours: hours, guide: guide),
            "</li>"
        ].joined(separator: "\n")
    }

    private static func card(
        _ stop: Stop,
        place: Place?,
        kind: StopKindStyle,
        hours: HoursNote?,
        guide: Guide
    ) -> String {
        let title = HTML.trimmed(stop.copy.title)
        var lines = [
            "<article class=\"\(stop.flexible ? "card optional" : "card")\">",
            eyebrow(kind, optional: stop.flexible),
            "<h3>\(titleHTML(title, place: place))</h3>"
        ]
        if let place, let name = shownPlaceName(place, title: title) {
            lines.append("<p class=\"stop-place\">\(HTML.placeLink(name, placeId: place.id))</p>")
        }
        if let body = HTML.nonBlank(stop.copy.body) {
            lines.append("<p class=\"body\">\(HTML.escape(body))</p>")
        }
        lines.append("<p class=\"meta\">\(meta(stop, place: place, hours: hours, guide: guide))</p>")
        if let alternative = alternativeLine(stop, place: place, guide: guide) {
            lines.append(alternative)
        }
        lines.append("</article>")
        return lines.joined(separator: "\n")
    }

    private static func eyebrow(_ kind: StopKindStyle, optional: Bool) -> String {
        let tag = optional ? "<span class=\"tag\">Optional</span>" : ""
        return "<p class=\"eyebrow\">\(HTML.escape(kind.eyebrow))\(tag)</p>"
    }

    /// The title links to the place's card when the stop has a place on the page.
    private static func titleHTML(_ title: String, place: Place?) -> String {
        guard let place else { return HTML.escape(title) }
        return "<a href=\"#\(HTML.placeAnchor(place.id))\">\(HTML.escape(title))</a>"
    }

    /// The place's name, unless it is the title or already inside it (ignoring case).
    private static func shownPlaceName(_ place: Place, title: String) -> String? {
        let name = HTML.trimmed(place.name)
        let lowerName = name.lowercased()
        let lowerTitle = title.lowercased()
        if lowerName == lowerTitle || lowerTitle.contains(lowerName) {
            return nil
        }
        return name
    }

    /// "50 min · Open until 16:00 · £", then the booking badge when the place must be booked ahead.
    private static func meta(_ stop: Stop, place: Place?, hours: HoursNote?, guide: Guide) -> String {
        var parts = [HTML.escape(RenderText.duration(minutes: stop.minutes))]
        if let hours {
            parts.append(hoursHTML(hours))
        }
        if let place, let price = priceText(place, guide: guide) {
            parts.append(HTML.escape(price))
        }
        var html = parts.joined(separator: " · ")
        if let place, place.booking.needed {
            html += " " + RenderPlaces.bookingBadge(place.booking.url)
        }
        return html
    }

    private static func priceText(_ place: Place, guide: Guide) -> String? {
        RenderText.price(level: place.priceLevel, currencyCode: guide.trip.budget.currencyCode)
    }

    private static func hoursHTML(_ note: HoursNote) -> String {
        let text = HTML.escape(note.text)
        return note.isUncertain ? "\(HTML.infoMark) \(text)" : text
    }

    /// "If it rains: Oink Hanover Street, 4 min away". The walk is left out when either place is unknown.
    private static func alternativeLine(_ stop: Stop, place: Place?, guide: Guide) -> String? {
        guard let alternative = stop.alternative, let other = guide.places[alternative.placeId] else {
            return nil
        }
        var line = alternativePrefix(alternative.reason) + HTML.placeLink(other.name, placeId: other.id)
        if let place {
            let minutes = StraightLineWalkTimes().minutes(
                from: place.location.coordinate,
                to: other.location.coordinate
            )
            line += ", \(RenderText.duration(minutes: minutes)) away"
        }
        return "<p class=\"alt\">\(line)</p>"
    }

    private static func alternativePrefix(_ reason: AlternativeReason) -> String {
        switch reason {
        case .rain: "If it rains: "
        case .closed: "If it's closed: "
        case .tired: "If you're tired: "
        }
    }
}
