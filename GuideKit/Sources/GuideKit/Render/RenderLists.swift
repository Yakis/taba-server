/// The lists beside the days (Eat, Drink, Photos, Groceries...): each list's title and caption, then one row per place.
enum RenderLists {
    /// The section for every list that has a place to show, in the guide's order. Nil when there is none.
    static func section(_ guide: Guide) -> String? {
        let lists = guide.lists.compactMap { listSection($0, guide: guide) }
        guard !lists.isEmpty else { return nil }
        return (["<section class=\"part\" id=\"lists\">"] + lists + ["</section>"]).joined(separator: "\n")
    }

    private static func listSection(_ list: PlaceList, guide: Guide) -> String? {
        let rows = list.placeIds.compactMap { guide.places[$0] }.map { row($0, guide: guide) }
        guard !rows.isEmpty else { return nil }
        var lines = [
            "<section class=\"list\">",
            "<h2>\(HTML.escape(HTML.trimmed(list.title)))</h2>"
        ]
        if let caption = HTML.nonBlank(list.caption) {
            lines.append("<p class=\"caption\">\(HTML.escape(caption))</p>")
        }
        lines.append("<ul class=\"list-rows\">")
        lines += rows
        lines += ["</ul>", "</section>"]
        return lines.joined(separator: "\n")
    }

    /// The place's name (linked to its card), then its tag and walk from the stay: "Quick bite · 6 min from the stay".
    private static func row(_ place: Place, guide: Guide) -> String {
        let tag = HTML.nonBlank(place.copy?.tag) ?? RenderText.placeKindLabel(place.kind)
        let walk = RenderStay.listText(to: place, guide: guide)
        let meta = [tag, walk].compactMap { $0 }.map { HTML.escape($0) }.joined(separator: " · ")
        return [
            "<li>",
            "<p class=\"row-name\">\(HTML.placeLink(place.name, placeId: place.id))</p>",
            "<p class=\"row-meta\">\(meta)</p>",
            "</li>"
        ].joined(separator: "\n")
    }
}
