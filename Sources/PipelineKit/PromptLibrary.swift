import Foundation

/// A versioned prompt. The body is used unchanged as instructions or a repair message.
public struct Prompt: Sendable, Equatable {
    public let id: String
    public let version: Int
    public let role: String
    public let output: String
    public let effort: String?
    public let tools: [String]
    public let metadata: [String: String]
    public let body: String
}

public enum PromptError: Error, Equatable {
    case missingResource(String)
    case missingFrontMatter
    case malformedField(String)
    case duplicateField(String)
    case missingField(String)
    case invalidVersion(String)
    case mismatchedID(expected: String, actual: String)
}

/// Loads the actual files in Prompts, not copies that can drift from the reviewed text.
public enum PromptLibrary {
    public static func load(_ id: String) throws -> Prompt {
        // Only known resource names are accepted; callers cannot use this as a file path.
        guard ["plan", "repair", "research", "ticket", "write"].contains(id),
              let url = Bundle.module.url(forResource: id, withExtension: "md", subdirectory: "Prompts") else {
            throw PromptError.missingResource(id)
        }
        let prompt = try parse(String(contentsOf: url, encoding: .utf8))
        guard prompt.id == id else {
            throw PromptError.mismatchedID(expected: id, actual: prompt.id)
        }
        return prompt
    }

    /// Parses the flat, scalar front-matter format used by these prompts, rejecting ambiguous input.
    public static func parse(_ text: String) throws -> Prompt {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---",
              let end = lines.indices.dropFirst().first(where: { lines[$0] == "---" }) else {
            throw PromptError.missingFrontMatter
        }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let colon = line.firstIndex(of: ":") else { throw PromptError.malformedField(line) }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { throw PromptError.malformedField(line) }
            guard fields[key] == nil else { throw PromptError.duplicateField(key) }
            fields[key] = value
        }
        func required(_ key: String) throws -> String {
            guard let value = fields[key] else { throw PromptError.missingField(key) }
            return value
        }
        let id = try required("id")
        let versionText = try required("version")
        guard let version = Int(versionText), version > 0 else { throw PromptError.invalidVersion(versionText) }
        let role = try required("role")
        let output = try required("output")
        let tools = fields["tools"].map {
            $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } ?? []
        // The separating blank line is formatting, not part of the instructions.
        var bodyLines = Array(lines[(end + 1)...])
        if bodyLines.first == "" { bodyLines.removeFirst() }
        let body = bodyLines.joined(separator: "\n")
        return Prompt(id: id, version: version, role: role, output: output, effort: fields["effort"],
                      tools: tools, metadata: fields, body: body)
    }
}
