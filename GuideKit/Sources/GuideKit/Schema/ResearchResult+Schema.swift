extension ResearchResult {
    /// The strict schema research must answer with. Finding kinds, confidence and suggested place kinds come from
    /// their enums.
    public static func schema() -> JSONSchema {
        let finding = JSONSchema.object([
            "id": .string,
            "kind": .enumOf(FindingKind.self),
            "title": .string,
            "summary": .string,
            "startDate": .nullable(.string),
            "endDate": .nullable(.string),
            "times": .nullable(.string),
            "placeName": .nullable(.string),
            "address": .nullable(.string),
            "url": .string,
            "sourceTitle": .string,
            "confidence": .enumOf(FindingConfidence.self),
            "onTripDates": .boolean
        ])
        let suggestedPlace = JSONSchema.object([
            "name": .string,
            "area": .string,
            "kind": .enumOf(PlaceKind.self),
            "why": .string
        ])
        return .object([
            "findings": .array(finding),
            "suggestedPlaces": .array(suggestedPlace),
            "searchNotes": .string
        ])
    }
}
