/// Reads a prompt file in the repo: its YAML front matter (between two "---" lines) is removed, and the body is kept.
public enum PromptFile {
    public static func body(of text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingWhitespace == "---" else {
            return text.trimmingWhitespace
        }
        guard let closing = lines.dropFirst().firstIndex(where: { $0.trimmingWhitespace == "---" }) else {
            return text.trimmingWhitespace
        }
        return lines[(closing + 1)...].joined(separator: "\n").trimmingWhitespace
    }
}

extension String {
    var trimmingWhitespace: String {
        var result = Substring(self)
        while let first = result.first, first.isWhitespace { result = result.dropFirst() }
        while let last = result.last, last.isWhitespace { result = result.dropLast() }
        return String(result)
    }
}
