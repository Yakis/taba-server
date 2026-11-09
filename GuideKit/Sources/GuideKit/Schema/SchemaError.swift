/// Thrown when a schema cannot be built from the values it was given.
public enum SchemaError: Error, Hashable, Sendable {
    /// A list of values became an enum, and the list was empty. OpenAI rejects an empty enum. `field` names the list,
    /// such as "candidateIds".
    case emptyEnum(field: String)
}

extension JSONSchema {
    /// A string enum of the given ids. Throws `SchemaError.emptyEnum` when there are none.
    static func idEnum(_ values: [String], field: String) throws(SchemaError) -> JSONSchema {
        guard !values.isEmpty else { throw SchemaError.emptyEnum(field: field) }
        return .stringEnum(values)
    }
}
