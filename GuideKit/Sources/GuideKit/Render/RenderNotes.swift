/// The notes after the places: the trip's notes as cards, "Good to know" with its sources, and "Tasting". Each part
/// is left out when it is empty.
enum RenderNotes {
    static func sections(_ guide: Guide) -> [String] {
        var sections: [String] = []
        let cards = tripNoteCards(guide.notes)
        if !cards.isEmpty {
            sections.append((["<section class=\"part\" id=\"notes\">", "<h2>Notes</h2>"] + cards + ["</section>"])
                .joined(separator: "\n"))
        }
        if let goodToKnow = goodToKnow(guide) {
            sections.append(goodToKnow)
        }
        if let tasting = tasting(guide) {
            sections.append(tasting)
        }
        return sections
    }

    /// Weather, Light, Backup plan and Rules of the trip, in that order. A note with no text has no card.
    private static func tripNoteCards(_ notes: GuideNotes?) -> [String] {
        guard let notes else { return [] }
        let items = [
            ("Weather", notes.weather),
            ("Light", notes.light),
            ("Backup plan", notes.backupPlan),
            ("Rules of the trip", notes.rules)
        ]
        var cards: [String] = []
        for (title, text) in items {
            guard let text = HTML.nonBlank(text) else { continue }
            cards.append(
                "<article class=\"card trip-note\"><h3>\(title)</h3><p>\(HTML.escape(text))</p></article>"
            )
        }
        return cards
    }

    private static func goodToKnow(_ guide: Guide) -> String? {
        let items = guide.practical.compactMap { fact -> String? in
            let text = HTML.trimmed(fact.text)
            guard !text.isEmpty else { return nil }
            var html = "<li>\(HTML.escape(text))"
            if let link = RenderSources.factLink(sourceId: fact.sourceId, in: guide) {
                html += " " + link
            }
            return html + "</li>"
        }
        guard !items.isEmpty else { return nil }
        return (["<section id=\"good-to-know\">", "<h2>Good to know</h2>", "<ul class=\"facts\">"]
            + items + ["</ul>", "</section>"]).joined(separator: "\n")
    }

    private static func tasting(_ guide: Guide) -> String? {
        let cards = guide.tasting.compactMap { item -> String? in
            guard let name = HTML.nonBlank(item.name) else { return nil }
            let note = HTML.nonBlank(item.note).map { "<p>\(HTML.escape($0))</p>" } ?? ""
            return "<article class=\"card taste\"><h3>\(HTML.escape(name))</h3>\(note)</article>"
        }
        guard !cards.isEmpty else { return nil }
        return (["<section id=\"tasting\">", "<h2>Tasting</h2>", "<div class=\"taste-grid\">"]
            + cards + ["</div>", "</section>"]).joined(separator: "\n")
    }
}
