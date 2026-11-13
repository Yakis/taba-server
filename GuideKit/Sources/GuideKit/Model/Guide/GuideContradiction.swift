/// Words in the guide's prose that contradict its facts, such as a hotel on a trip with no stay. A guide with any of
/// these is not finished, however well the words read: the facts win over the prose.
public struct GuideContradiction: Hashable, Sendable {
    /// Where the words are, such as "stops[d1-s3].body", "notes.rules" or "openQuestions[2]".
    public let path: String
    /// The words that contradict the facts.
    public let words: String
    /// The whole text they are in.
    public let text: String
    /// What the facts say instead, in one sentence for the writer or a reviewer.
    public let reason: String

    public init(path: String, words: String, text: String, reason: String) {
        self.path = path
        self.words = words
        self.text = text
        self.reason = reason
    }
}
