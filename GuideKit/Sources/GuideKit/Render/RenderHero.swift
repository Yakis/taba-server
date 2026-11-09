/// The title block at the top of the page, and the "Check before you go" list under it.
enum RenderHero {
    /// The hero title, or "<city> guide" for a guide without one. Also the page's `<title>`.
    static func title(_ guide: Guide) -> String {
        HTML.nonBlank(guide.hero?.title) ?? "\(guide.trip.destination.name) guide"
    }

    /// The dark band: the city, the title, the subtitle, the dates, a one-line summary and the tagline.
    static func band(_ guide: Guide) -> String {
        var lines = [
            "<header class=\"hero\">",
            "<div class=\"wrap\">",
            "<p class=\"eyebrow\">\(HTML.escape(guide.trip.destination.name))</p>",
            "<h1>\(HTML.escape(title(guide)))</h1>"
        ]
        if let subtitle = HTML.nonBlank(guide.hero?.subtitle) {
            lines.append("<p class=\"subtitle\">\(HTML.escape(subtitle))</p>")
        }
        lines.append("<p class=\"dates\">\(HTML.escape(RenderText.tripDates(guide.trip.dates)))</p>")
        if let summary = summary(guide) {
            lines.append("<p class=\"summary\">\(HTML.escape(summary))</p>")
        }
        if let tagline = HTML.nonBlank(guide.hero?.tagline) {
            lines.append("<p class=\"tagline\"><em>\(HTML.escape(tagline))</em></p>")
        }
        lines += ["</div>", "</header>"]
        return lines.joined(separator: "\n")
    }

    /// "1–9° · Sunrise 08:02 · Sunset 15:49": the temperatures over every day with weather, then the first day's sun.
    static func summary(_ guide: Guide) -> String? {
        let outlooks = guide.days.compactMap(\.weather)
        var parts: [String] = []
        if let lowest = outlooks.compactMap(\.lowCelsius).min(),
           let highest = outlooks.compactMap(\.highCelsius).max() {
            parts.append(lowest == highest ? "\(lowest)°" : "\(lowest)–\(highest)°")
        }
        if let first = guide.days.first, let sun = RenderText.sunLine(on: first.date, guide: guide) {
            parts.append(sun)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The open questions as a checklist, or nil when there are none.
    static func checks(_ guide: Guide) -> String? {
        let questions = (guide.openQuestions ?? []).compactMap { HTML.nonBlank($0) }
        guard !questions.isEmpty else { return nil }
        var lines = [
            "<section class=\"checks\">",
            "<h2>Check before you go</h2>",
            "<ul class=\"checklist\">"
        ]
        lines += questions.map { "<li>\(HTML.escape($0))</li>" }
        lines += ["</ul>", "</section>"]
        return lines.joined(separator: "\n")
    }
}
