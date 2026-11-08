/// Something worth trying, with a short note.
public struct TasteItem: Hashable, Sendable, Codable {
    public let name: String
    public let note: String

    public init(name: String, note: String) {
        self.name = name
        self.note = note
    }
}
