/// What the AI returns when it plans a guide. A subset of `Guide`: no legs, checks or derived numbers.
public struct PlanDraft: Hashable, Sendable, Codable {
    public let days: [PlanDraftDay]
    public let lists: [PlaceList]
    public let tasting: [TasteItem]
    public let notes: String

    public init(days: [PlanDraftDay], lists: [PlaceList], tasting: [TasteItem], notes: String) {
        self.days = days
        self.lists = lists
        self.tasting = tasting
        self.notes = notes
    }
}
