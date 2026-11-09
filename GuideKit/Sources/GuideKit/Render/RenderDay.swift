/// One day of the guide: its header (title, summary, weather and sun) and its timeline of stops.
enum RenderDay {
    static func section(_ day: Day, index: Int, guide: Guide) -> String {
        var lines = [
            "<section class=\"day\" id=\"day-\(index + 1)\">",
            "<header class=\"day-head\">",
            "<p class=\"eyebrow\">Day \(index + 1) · \(HTML.escape(RenderText.dayTitleDate(day.date)))</p>",
            "<h2>\(HTML.escape(HTML.trimmed(day.copy.title)))</h2>"
        ]
        if let summary = HTML.nonBlank(day.copy.summary) {
            lines.append("<p class=\"summary\">\(HTML.escape(summary))</p>")
        }
        if let conditions = conditions(day, guide: guide) {
            lines.append("<p class=\"conditions\">\(HTML.escape(conditions))</p>")
        }
        lines.append("</header>")
        if !day.stops.isEmpty {
            lines.append("<ol class=\"timeline\">")
            lines += timeline(day, guide: guide)
            lines.append("</ol>")
        }
        lines.append("</section>")
        return lines.joined(separator: "\n")
    }

    /// "Rain likely, 8° · Sunrise 08:07 · Sunset 15:51". Nil when neither the weather nor the sun is known.
    private static func conditions(_ day: Day, guide: Guide) -> String? {
        let parts = [
            RenderText.weatherLine(day.weather),
            RenderText.sunLine(on: day.date, guide: guide)
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Every stop's rows in order. Each stop after the first is told the place of the stop before it, so a walk
    /// between two stops at one place is left out.
    private static func timeline(_ day: Day, guide: Guide) -> [String] {
        var rows: [String] = []
        for (position, stop) in day.stops.enumerated() {
            let previous = position > 0 ? day.stops[position - 1].placeId : nil
            rows += RenderStop.rows(stop, previousPlaceId: previous, date: day.date, guide: guide)
        }
        return rows
    }
}
