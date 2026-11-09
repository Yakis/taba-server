/// Turns a guide into one self-contained HTML page: inline CSS, no scripts, no remote fonts or images.
///
/// The page follows the paper style of the TABA design guide. It prints as A4, with every day starting a new page.
/// The output is deterministic: the same guide always gives the same text, because places are sorted by name and the
/// clock, the locale and the device are never read.
public struct GuideHTMLRenderer: Sendable {
    public init() {}

    /// The page for `guide`, top to bottom: the hero, the things to check, every day, the lists, every place, the
    /// notes and the sources.
    /// - Parameter guide: The guide to show. Its places appear in name order, whatever order the dictionary gives.
    public func render(_ guide: Guide) -> String {
        var sections: [String] = []
        if let checks = RenderHero.checks(guide) {
            sections.append(checks)
        }
        for (index, day) in guide.days.enumerated() {
            sections.append(RenderDay.section(day, index: index, guide: guide))
        }
        if let lists = RenderLists.section(guide) {
            sections.append(lists)
        }
        if let places = RenderPlaces.section(guide) {
            sections.append(places)
        }
        sections += RenderNotes.sections(guide)
        if let sources = RenderSources.section(guide) {
            sections.append(sources)
        }
        return RenderPage.document(
            title: RenderHero.title(guide),
            hero: RenderHero.band(guide),
            sections: sections
        )
    }
}
