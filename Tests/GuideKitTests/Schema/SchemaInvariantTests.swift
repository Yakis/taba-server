import Foundation
import GuideKit
import Testing

struct SchemaInvariantTests {
    private let candidates = ["manual:cafe", "osm:node/1", "osm:way/2"]
    private let stopIds = ["d1-s1", "d1-s2"]

    private func walk(_ schema: JSONSchema) throws -> SchemaWalk {
        SchemaWalk(root: try parsedJSON(try encodedJSON(schema)))
    }

    private func planSchema() throws -> JSONSchema {
        try PlanDraft.schema(candidateIds: candidates)
    }

    private func copySchema() throws -> JSONSchema {
        try GuideCopy.schema(stopIds: stopIds, placeIds: candidates, listKeys: ListKey.allCases)
    }

    @Test func planSchemaIsStrict() throws {
        let result = try walk(planSchema())
        #expect(result.problems.isEmpty, "\(result.problems)")
        #expect(result.objectCount > 0)
    }

    @Test func guideCopySchemaIsStrict() throws {
        let result = try walk(copySchema())
        #expect(result.problems.isEmpty, "\(result.problems)")
        #expect(result.objectCount > 0)
    }

    @Test func researchSchemaIsStrict() throws {
        let result = try walk(ResearchResult.schema())
        #expect(result.problems.isEmpty, "\(result.problems)")
        #expect(result.objectCount > 0)
    }

    @Test func walkerRejectsAnObjectThatAllowsExtraKeys() throws {
        let property = #""a":{"type":"string"}"#
        let open = #"{"type":"object","properties":{\#(property)},"required":["a"],"additionalProperties":true}"#
        #expect(try SchemaWalk(root: parsedJSON(open)).problems.count == 1)
        let head = #"{"type":"object","properties":{\#(property)},"#
        let partlyRequired = head + #""required":[],"additionalProperties":false}"#
        #expect(try SchemaWalk(root: parsedJSON(partlyRequired)).problems.count == 1)
    }

    @Test func walkerRejectsKeywordsOutsideTheSubset() throws {
        let formatted = #"{"type":"string","format":"date"}"#
        #expect(try SchemaWalk(root: parsedJSON(formatted)).problems.count == 1)
    }

    @Test func planEnumsAreTheSwiftCases() throws {
        let enums = try walk(planSchema()).enums
        #expect(enums.contains(StopKind.allCases.map(\.rawValue)))
        #expect(enums.contains(MealSlot.allCases.map(\.rawValue)))
        #expect(enums.contains(AlternativeReason.allCases.map(\.rawValue)))
        #expect(enums.contains(ListKey.allCases.map(\.rawValue)))
    }

    @Test func planSchemaOffersTheCandidateIds() throws {
        let enums = try walk(planSchema()).enums
        #expect(enums.contains(candidates))
    }

    @Test func guideCopyEnumsAreTheIdsItWasGiven() throws {
        let enums = try walk(copySchema()).enums
        #expect(enums.contains(stopIds))
        #expect(enums.contains(candidates))
        #expect(enums.contains(ListKey.allCases.map(\.rawValue)))
    }

    @Test func emptyCandidateListThrows() {
        #expect(throws: SchemaError.emptyEnum(field: "candidateIds")) {
            try PlanDraft.schema(candidateIds: [])
        }
    }

    @Test func emptyStopListThrows() {
        #expect(throws: SchemaError.emptyEnum(field: "stopIds")) {
            try GuideCopy.schema(stopIds: [], placeIds: candidates, listKeys: ListKey.allCases)
        }
    }

    @Test func emptyPlaceListThrows() {
        #expect(throws: SchemaError.emptyEnum(field: "placeIds")) {
            try GuideCopy.schema(stopIds: stopIds, placeIds: [], listKeys: ListKey.allCases)
        }
    }

    @Test func emptyListKeyListThrows() {
        #expect(throws: SchemaError.emptyEnum(field: "listKeys")) {
            try GuideCopy.schema(stopIds: stopIds, placeIds: candidates, listKeys: [])
        }
    }

    @Test func researchEnumsAreTheSwiftCases() throws {
        let enums = try walk(ResearchResult.schema()).enums
        #expect(enums.contains(FindingKind.allCases.map(\.rawValue)))
        #expect(enums.contains(FindingConfidence.allCases.map(\.rawValue)))
        #expect(enums.contains(PlaceKind.allCases.map(\.rawValue)))
    }

    @Test func nullableScalarListsNullAsATypeName() throws {
        let schema = JSONSchema.nullable(.string)
        #expect(try canonicalJSON(encodedJSON(schema)) == canonicalJSON(#"{"type":["string","null"]}"#))
    }

    @Test func nullableEnumUsesAnyOfWithNull() throws {
        let schema = JSONSchema.nullable(.stringEnum(["a", "b"]))
        let expected = #"{"anyOf":[{"enum":["a","b"],"type":"string"},{"type":"null"}]}"#
        #expect(try canonicalJSON(encodedJSON(schema)) == canonicalJSON(expected))
    }

    @Test func nullableObjectUsesAnyOfWithNull() throws {
        let schema = JSONSchema.nullable(.object(["a": .string]))
        let object = #"{"additionalProperties":false,"properties":{"a":{"type":"string"}},"required":["a"]"#
        let expected = #"{"anyOf":[\#(object),"type":"object"},{"type":"null"}]}"#
        #expect(try canonicalJSON(encodedJSON(schema)) == canonicalJSON(expected))
    }

    @Test func textFormatWrapsTheSchemaAsStrictJSON() throws {
        let schema = JSONSchema.object(["a": .string])
        let wrapped = schema.textFormat(named: "sample")
        let object = #"{"additionalProperties":false,"properties":{"a":{"type":"string"}},"required":["a"]"#
        let expected = #"{"name":"sample","schema":\#(object),"type":"object"},"strict":true,"type":"json_schema"}"#
        #expect(try canonicalJSON(encodedJSON(wrapped)) == canonicalJSON(expected))
    }

    @Test func encodedSamplesOnlyUseKeysTheSchemaNames() throws {
        let planKeys = SchemaWalk.keys(in: try parsedJSON(encodedJSON(SampleGuide.planDraft())))
        let planNames = try walk(planSchema()).propertyNames
        #expect(planKeys.isSubset(of: planNames), "\(planKeys.subtracting(planNames))")

        let copyKeys = SchemaWalk.keys(in: try parsedJSON(encodedJSON(SampleGuide.guideCopy())))
        let copyNames = try walk(copySchema()).propertyNames
        #expect(copyKeys.isSubset(of: copyNames), "\(copyKeys.subtracting(copyNames))")

        let researchKeys = SchemaWalk.keys(in: try parsedJSON(encodedJSON(SampleGuide.researchResult())))
        let researchNames = try walk(ResearchResult.schema()).propertyNames
        #expect(researchKeys.isSubset(of: researchNames), "\(researchKeys.subtracting(researchNames))")
    }
}
