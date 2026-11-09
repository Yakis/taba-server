/// Who is travelling and any mobility notes, such as "stairs fine".
public struct Party: Hashable, Sendable, Codable {
    public let adults: Int
    public let children: Int
    public let mobilityNotes: [String]

    public init(adults: Int, children: Int, mobilityNotes: [String]) {
        self.adults = adults
        self.children = children
        self.mobilityNotes = mobilityNotes
    }
}
