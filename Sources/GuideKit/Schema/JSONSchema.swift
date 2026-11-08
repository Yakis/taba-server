/// A JSON Schema written in the subset that OpenAI's strict structured outputs accept.
///
/// Every object lists all its properties as `required` and allows no others. An optional value is `nullable`.
/// The schema never uses `format`, `pattern`, or minimum and maximum keywords: code checks those after decoding.
public indirect enum JSONSchema: Hashable, Sendable, Encodable {
    case string
    case integer
    case number
    case boolean
    /// A string that must be one of these values.
    case stringEnum([String])
    case array(JSONSchema)
    /// An object with exactly these properties, in this order. All of them are required.
    case object([Property])
    /// The schema or null. Scalars list both types. Other schemas are wrapped in `anyOf` with a null branch.
    case nullable(JSONSchema)

    /// One named property of an object.
    public struct Property: Hashable, Sendable {
        public let name: String
        public let schema: JSONSchema

        public init(_ name: String, _ schema: JSONSchema) {
            self.name = name
            self.schema = schema
        }
    }

    /// An object from name and schema pairs, in the order given.
    public static func object(_ fields: KeyValuePairs<String, JSONSchema>) -> JSONSchema {
        JSONSchema.object(fields.map { Property($0.key, $0.value) })
    }

    /// A string enum with the raw value of every case, in declaration order.
    public static func enumOf<Value: CaseIterable & RawRepresentable>(
        _ type: Value.Type
    ) -> JSONSchema where Value.RawValue == String {
        .stringEnum(type.allCases.map(\.rawValue))
    }

    /// The JSON type name for a scalar, or nil for a schema that is not a scalar.
    private var scalarName: String? {
        switch self {
        case .string: "string"
        case .integer: "integer"
        case .number: "number"
        case .boolean: "boolean"
        default: nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .string, .integer, .number, .boolean:
            var container = encoder.container(keyedBy: SchemaKey.self)
            try container.encode(scalarName, forKey: .type)
        case .stringEnum(let values):
            var container = encoder.container(keyedBy: SchemaKey.self)
            try container.encode("string", forKey: .type)
            try container.encode(values, forKey: .values)
        case .array(let items):
            var container = encoder.container(keyedBy: SchemaKey.self)
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
        case .object(let properties):
            try Self.encodeObject(properties, to: encoder)
        case .nullable(let inner):
            try Self.encodeNullable(inner, to: encoder)
        }
    }

    private static func encodeObject(_ properties: [Property], to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        try container.encode("object", forKey: .type)
        var named = container.nestedContainer(keyedBy: PropertyName.self, forKey: .properties)
        for property in properties {
            try named.encode(property.schema, forKey: PropertyName(property.name))
        }
        try container.encode(properties.map(\.name), forKey: .required)
        try container.encode(false, forKey: .additionalProperties)
    }

    private static func encodeNullable(_ inner: JSONSchema, to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        if let name = inner.scalarName {
            try container.encode([name, "null"], forKey: .type)
        } else {
            var branches = container.nestedUnkeyedContainer(forKey: .anyOf)
            try branches.encode(inner)
            try branches.encode(NullSchema())
        }
    }
}

/// The keywords this builder writes.
private enum SchemaKey: String, CodingKey {
    case type
    case values = "enum"
    case items
    case properties
    case required
    case additionalProperties
    case anyOf
}

/// A property name used as a dynamic coding key.
private struct PropertyName: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ name: String) {
        self.stringValue = name
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

/// The `{"type": "null"}` branch of a nullable schema.
private struct NullSchema: Encodable {
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: SchemaKey.self)
        try container.encode("null", forKey: .type)
    }
}
