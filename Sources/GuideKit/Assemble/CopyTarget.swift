/// The item a piece of copy is for: a day (by date), a stop, a place or a pick list.
public enum CopyTarget: Hashable, Sendable {
    case day(LocalDate)
    /// The plan's stop id, from before assembly renumbered it.
    case stop(String)
    case place(String)
    case list(ListKey)
}
