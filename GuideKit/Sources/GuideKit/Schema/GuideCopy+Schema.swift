extension GuideCopy {
    /// The strict schema the writer must answer with. Stop, place and list ids are enums of the ids in the plan,
    /// so the writer cannot invent one. Throws `SchemaError.emptyEnum` when any of those lists is empty. Pass only
    /// the places that need copy (see `PlaceKind.needsCopy`).
    public static func schema(
        stopIds: [String],
        placeIds: [String],
        listKeys: [ListKey]
    ) throws(SchemaError) -> JSONSchema {
        let stopId = try JSONSchema.idEnum(stopIds, field: "stopIds")
        let placeId = try JSONSchema.idEnum(placeIds, field: "placeIds")
        let listKey = try JSONSchema.idEnum(listKeys.map(\.rawValue), field: "listKeys")
        let hero = JSONSchema.object([
            "title": .string,
            "subtitle": .string,
            "tagline": .string
        ])
        let day = JSONSchema.object([
            "date": .string,
            "title": .string,
            "summary": .string
        ])
        let stop = JSONSchema.object([
            "id": stopId,
            "title": .string,
            "body": .string,
            "actionLabel": .nullable(.string)
        ])
        let place = JSONSchema.object([
            "id": placeId,
            "tag": .string,
            "blurb": .string
        ])
        let list = JSONSchema.object([
            "key": listKey,
            "title": .string,
            "caption": .string
        ])
        let tasteItem = JSONSchema.object([
            "name": .string,
            "note": .string
        ])
        let notes = JSONSchema.object([
            "weather": .string,
            "light": .string,
            "backupPlan": .string,
            "rules": .string
        ])
        return .object([
            "hero": hero,
            "days": .array(day),
            "stops": .array(stop),
            "places": .array(place),
            "lists": .array(list),
            "tasting": .array(tasteItem),
            "notes": notes
        ])
    }
}
