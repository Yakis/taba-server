extension PlaceKind {
    /// Whether the writer describes a place of this kind. Lodging, luggage stores and stations are named by the plan,
    /// not written about, so they need no copy. Callers use this to choose the place ids for `GuideCopy.schema`.
    public var needsCopy: Bool {
        switch self {
        case .lodging, .luggage, .station:
            false
        default:
            true
        }
    }
}
