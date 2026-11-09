/// What a place's hours say about one stop, for example "Open until 16:00", or "Hours not confirmed" when they are
/// unknown. `isUncertain` lets the page mark that line with the info symbol.
struct HoursNote: Equatable {
    let text: String
    let isUncertain: Bool

    /// A note about hours that are known.
    static func known(_ text: String) -> HoursNote {
        HoursNote(text: text, isUncertain: false)
    }
}
