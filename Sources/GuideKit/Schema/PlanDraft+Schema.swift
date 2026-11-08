extension PlanDraft {
    /// The strict schema the planner must answer with.
    ///
    /// Place ids are an enum of `candidateIds`, so the planner cannot invent a place. Stop kinds, meal slots,
    /// alternative reasons and list keys come from their enums. Throws `SchemaError.emptyEnum` when there are no
    /// candidates, because an empty enum is not accepted.
    public static func schema(candidateIds: [String]) throws(SchemaError) -> JSONSchema {
        let placeId = try JSONSchema.idEnum(candidateIds, field: "candidateIds")
        let alternative = JSONSchema.nullable(.object([
            "placeId": placeId,
            "reason": .enumOf(AlternativeReason.self)
        ]))
        let stop = JSONSchema.object([
            "id": .string,
            "placeId": .nullable(placeId),
            "kind": .enumOf(StopKind.self),
            "mealSlot": .nullable(.enumOf(MealSlot.self)),
            "start": .string,
            "minutes": .integer,
            "flexible": .boolean,
            "alternative": alternative,
            "reason": .string,
            "findingIds": .array(.string)
        ])
        let day = JSONSchema.object([
            "date": .string,
            "theme": .string,
            "stops": .array(stop)
        ])
        let list = JSONSchema.object([
            "key": .enumOf(ListKey.self),
            "placeIds": .array(placeId)
        ])
        let skippedMeal = JSONSchema.object([
            "date": .string,
            "slot": .enumOf(MealSlot.self),
            "reason": .string
        ])
        return .object([
            "days": .array(day),
            "lists": .array(list),
            "skippedMeals": .array(skippedMeal),
            "openQuestions": .array(.string),
            "changes": .array(.string)
        ])
    }
}
