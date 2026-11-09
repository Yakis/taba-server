/// The `text.format` value of a Responses request: a named, strict JSON schema.
///
/// Encodes as `{"type": "json_schema", "name": ..., "strict": true, "schema": ...}`.
public struct TextFormat: Hashable, Sendable, Encodable {
    public let name: String
    public let schema: JSONSchema

    public init(name: String, schema: JSONSchema) {
        self.name = name
        self.schema = schema
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: FormatKey.self)
        try container.encode("json_schema", forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(true, forKey: .strict)
        try container.encode(schema, forKey: .schema)
    }
}

extension JSONSchema {
    /// Wraps this schema as the `text.format` value for a request, with the name OpenAI shows in logs.
    public func textFormat(named name: String) -> TextFormat {
        TextFormat(name: name, schema: self)
    }
}

/// The keys of the `text.format` wrapper.
private enum FormatKey: String, CodingKey {
    case type
    case name
    case strict
    case schema
}
