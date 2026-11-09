import Foundation

/// Walks an encoded JSON Schema and checks the rules OpenAI's strict mode needs. It also collects what the tests
/// compare: every enum, every property name, and the number of objects seen.
struct SchemaWalk {
    private(set) var problems: [String] = []
    private(set) var enums: [[String]] = []
    private(set) var propertyNames: Set<String> = []
    private(set) var objectCount = 0

    /// Keywords the builder must never write: strict mode does not accept them, and code checks those rules instead.
    private static let forbidden: Set<String> = [
        "format", "pattern",
        "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
        "minLength", "maxLength", "minItems", "maxItems", "multipleOf", "uniqueItems",
        "minProperties", "maxProperties"
    ]

    init(root: Any) {
        visit(root, at: "$")
    }

    private mutating func visit(_ node: Any, at path: String) {
        if let items = node as? [Any] {
            for (index, item) in items.enumerated() {
                visit(item, at: "\(path)[\(index)]")
            }
            return
        }
        guard let dict = node as? [String: Any] else { return }
        for key in dict.keys.sorted() where Self.forbidden.contains(key) {
            problems.append("\(path) uses \(key)")
        }
        if let values = dict["enum"] {
            if let names = values as? [String] {
                enums.append(names)
            } else {
                problems.append("\(path) has an enum that is not a list of strings")
            }
        }
        if dict["type"] as? String == "object" {
            checkObject(dict, at: path)
        }
        if let properties = dict["properties"] as? [String: Any] {
            propertyNames.formUnion(properties.keys)
        }
        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            visit(value, at: "\(path).\(key)")
        }
    }

    private mutating func checkObject(_ dict: [String: Any], at path: String) {
        objectCount += 1
        let properties = dict["properties"] as? [String: Any] ?? [:]
        let names = Set(properties.keys)
        let required = dict["required"] as? [String] ?? []
        if (dict["additionalProperties"] as? Bool) != false {
            problems.append("\(path) does not set additionalProperties to false")
        }
        if required.count != Set(required).count || Set(required) != names {
            problems.append("\(path) does not list exactly its properties as required")
        }
    }

    /// Every object key anywhere in a parsed JSON value.
    static func keys(in node: Any) -> Set<String> {
        if let items = node as? [Any] {
            return items.reduce(into: Set<String>()) { $0.formUnion(keys(in: $1)) }
        }
        guard let dict = node as? [String: Any] else { return [] }
        var result = Set(dict.keys)
        for value in dict.values {
            result.formUnion(keys(in: value))
        }
        return result
    }
}

/// Parses JSON text into the plain values JSONSerialization returns.
func parsedJSON(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
}

/// The same JSON with sorted keys and no spaces, so two texts can be compared for meaning rather than layout.
func canonicalJSON(_ text: String) throws -> String {
    let value = try parsedJSON(text)
    let bytes = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
    guard let text = String(bytes: bytes, encoding: .utf8) else { throw NotUTF8Error() }
    return text
}
