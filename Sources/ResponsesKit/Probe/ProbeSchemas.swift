/// The structured outputs the probe asks for. Strict mode: every property is required and no extra keys are allowed.
public enum ProbeSchemas {
    /// A small PlanDraft-like shape: days, each with stops that pick a placeId from the candidates.
    public static func planDraft(candidateIds: [String]) -> StructuredOutput {
        let stop: JSONValue = .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": strings(["placeId", "kind", "start", "minutes", "reason"]),
            "properties": .object([
                "placeId": .object(["type": .string("string"), "enum": strings(candidateIds)]),
                "kind": .object([
                    "type": .string("string"),
                    "enum": strings(["sight", "meal", "drink", "rest", "travel", "logistics"])
                ]),
                "start": .object(["type": .string("string")]),
                "minutes": .object(["type": .string("integer")]),
                "reason": .object(["type": .string("string")])
            ])
        ])
        let day: JSONValue = .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": strings(["date", "stops"]),
            "properties": .object([
                "date": .object(["type": .string("string")]),
                "stops": .object(["type": .string("array"), "items": stop])
            ])
        ])
        let schema: JSONValue = .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": strings(["days", "openQuestions"]),
            "properties": .object([
                "days": .object(["type": .string("array"), "items": day]),
                "openQuestions": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
            ])
        ])
        return StructuredOutput(name: "plan_draft", schema: schema)
    }

    /// A small research shape: findings with a title, url and summary, and a note on what was not confirmed.
    public static let research: StructuredOutput = {
        let finding: JSONValue = .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": strings(["title", "url", "summary"]),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "url": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")])
            ])
        ])
        let schema: JSONValue = .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": strings(["findings", "searchNotes"]),
            "properties": .object([
                "findings": .object(["type": .string("array"), "items": finding]),
                "searchNotes": .object(["type": .string("string")])
            ])
        ])
        return StructuredOutput(name: "research_result", schema: schema)
    }()

    private static func strings(_ values: [String]) -> JSONValue {
        .array(values.map { .string($0) })
    }
}
