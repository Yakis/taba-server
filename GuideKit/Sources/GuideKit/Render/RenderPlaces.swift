/// Every place in the guide, sorted by name then id, each as a card the lists and stops link to.
enum RenderPlaces {
    /// The section with one card per place. Nil when the guide has no places.
    static func section(_ guide: Guide) -> String? {
        let places = guide.places.values.sorted { lhs, rhs in
            (lhs.name, lhs.id) < (rhs.name, rhs.id)
        }
        guard !places.isEmpty else { return nil }
        var lines = ["<section class=\"part\" id=\"places\">", "<h2>Places</h2>"]
        lines += places.map { card($0, guide: guide) }
        lines.append("</section>")
        return lines.joined(separator: "\n")
    }

    /// "Book ahead", linked to the booking page when its address is a web address.
    static func bookingBadge(_ url: String?) -> String {
        if let address = HTML.webAddress(url) {
            return HTML.link("Book ahead", to: address, class: "badge")
        }
        return "<span class=\"badge\">Book ahead</span>"
    }

    private static func card(_ place: Place, guide: Guide) -> String {
        let tag = HTML.nonBlank(place.copy?.tag) ?? RenderText.placeKindLabel(place.kind)
        var lines = [
            "<article class=\"card place\" id=\"\(HTML.placeAnchor(place.id))\">",
            "<p class=\"eyebrow\">\(HTML.escape(tag))</p>",
            "<h3>\(HTML.escape(place.name))</h3>"
        ]
        if let blurb = HTML.nonBlank(place.copy?.blurb) {
            lines.append("<p class=\"blurb\">\(HTML.escape(blurb))</p>")
        }
        let rows = infoRows(place, guide: guide)
        if !rows.isEmpty {
            lines.append("<dl class=\"info\">")
            lines += rows
            lines.append("</dl>")
        }
        lines += factLines(place, guide: guide)
        lines.append("</article>")
        return lines.joined(separator: "\n")
    }

    /// The info block: hours on each trip date, address, walk, price, booking, website and phone. A row is left out
    /// when there is nothing to say.
    private static func infoRows(_ place: Place, guide: Guide) -> [String] {
        var rows: [String] = []
        if let hours = hoursHTML(place, tripDates: guide.trip.dates) {
            rows.append(row("Hours", hours))
        }
        if let address = addressHTML(place) {
            rows.append(row("Address", address))
        }
        if let walk = RenderStay.walkText(to: place, guide: guide) {
            rows.append(row("Walk", HTML.escape(walk)))
        }
        if let price = RenderText.price(level: place.priceLevel, currencyCode: guide.trip.budget.currencyCode) {
            rows.append(row("Price", HTML.escape(price)))
        }
        if place.booking.needed {
            rows.append(row("Booking", bookingBadge(place.booking.url)))
        }
        if let website = HTML.webAddress(place.website), let host = HTML.displayHost(website) {
            rows.append(row("Website", HTML.link(host, to: website)))
        }
        if let phone = HTML.nonBlank(place.phone), phone.contains(where: { $0.isNumber }) {
            rows.append(row("Phone", HTML.escape(phone)))
        }
        return rows
    }

    private static func row(_ label: String, _ html: String) -> String {
        "<dt>\(label)</dt><dd>\(html)</dd>"
    }

    /// One line per trip date, first date first. Nil when the place's hours are not shown at all: unknown hours
    /// for a kind of place that has none to confirm.
    private static func hoursHTML(_ place: Place, tripDates: TripDates) -> String? {
        guard place.hours.hoursKnown else {
            if RenderHours.withoutHours.contains(place.kind) {
                return nil
            }
            return "\(HTML.infoMark) Hours not confirmed, check before you go"
        }
        var items: [String] = []
        var date: LocalDate? = tripDates.start
        while let current = date, current <= tripDates.end {
            let periods = RenderHours.periods(on: current, in: place.hours)
            items.append("<li>\(HTML.escape(RenderText.shortDay(current))): \(RenderHours.dayText(periods))</li>")
            date = current.adding(days: 1)
        }
        return "<ul class=\"hours\">" + items.joined() + "</ul>"
    }

    private static func addressHTML(_ place: Place) -> String? {
        let address = HTML.nonBlank(place.location.address)
        guard address != nil || place.location.approximate else { return nil }
        var html = address.map { HTML.escape($0) } ?? ""
        if place.location.approximate {
            if !html.isEmpty {
                html += "<br>"
            }
            html += "<span class=\"note\">Approximate location</span>"
        }
        return html
    }

    /// Each checked fact, with its source as a link when the source has a web address.
    private static func factLines(_ place: Place, guide: Guide) -> [String] {
        place.facts.map { fact in
            var html = "<p class=\"fact\">\(HTML.escape(HTML.trimmed(fact.text)))"
            if let link = RenderSources.factLink(sourceId: fact.sourceId, in: guide) {
                html += " " + link
            }
            return html + "</p>"
        }
    }
}
