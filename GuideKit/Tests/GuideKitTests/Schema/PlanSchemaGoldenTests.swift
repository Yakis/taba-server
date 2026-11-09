import GuideKit
import Testing

struct PlanSchemaGoldenTests {
    /// The plan schema for the Edinburgh places, compared byte for byte with `Fixtures/plan-schema.json`. The file
    /// ends with one newline. A change to the schema fails this test, so the new text shows up in review.
    @Test func planSchemaForEdinburghMatchesTheGoldenFile() throws {
        let guide = try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghMockData())
        let schema = try PlanDraft.schema(candidateIds: guide.places.keys.sorted())
        let encoded = try encodedJSON(schema) + "\n"
        let golden = try Fixture.planSchemaText()
        #expect(encoded == golden, "The plan schema changed. Review the diff and update Fixtures/plan-schema.json.")
    }
}
