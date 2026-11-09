/// Every source the guide checked its facts against: the title linked to the page, and the day it was checked.
enum RenderSources {
    /// The section, or nil when the guide has no sources.
    static func section(_ guide: Guide) -> String? {
        guard !guide.sources.isEmpty else { return nil }
        let items = guide.sources.map { source in
            let title = HTML.nonBlank(source.title) ?? source.url
            return "<li>\(HTML.link(title, to: source.url)) "
                + "<span class=\"muted\">checked \(RenderText.shortDate(source.checkedAt))</span></li>"
        }
        return (["<section class=\"sources\">", "<h2>Sources</h2>", "<ol>"] + items + ["</ol>", "</section>"])
            .joined(separator: "\n")
    }

    /// "Source: example.com", linked to the source's page, for the source with `sourceId`. Nil when the guide has no
    /// such source or its address is not a web address.
    static func factLink(sourceId: String, in guide: Guide) -> String? {
        guard let source = guide.sources.first(where: { $0.id == sourceId }),
              let address = HTML.webAddress(source.url),
              let host = HTML.displayHost(address)
        else {
            return nil
        }
        return HTML.link("Source: \(host)", to: address, class: "source")
    }
}
