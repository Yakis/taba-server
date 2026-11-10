import Foundation
import GuideKit
import PipelineKit
import Testing

struct ResearchInterestsTests {
    private func decode(_ json: String) throws -> ResearchResult {
        try JSONDecoder().decode(ResearchResult.self, from: Data(json.utf8))
    }

    @Test func aResearchAnswerWithInterestsDecodes() throws {
        let research = try decode("""
        {"findings":[],"searchNotes":"none","suggestedPlaces":[{"name":"Circus Lane","area":"New Town",
        "kind":"street","why":"Colourful doors.","interests":["Photography"]}]}
        """)
        #expect(research.suggestedPlaces.first?.interests == ["Photography"])
        #expect(research.suggestedPlaces.first?.kind == .street)
    }

    @Test func aResearchAnswerFromBeforeInterestsStillDecodes() throws {
        let research = try decode("""
        {"findings":[],"searchNotes":"none","suggestedPlaces":[{"name":"Calton Hill","area":"Calton",
        "kind":"viewpoint","why":"Wide views."}]}
        """)
        #expect(research.suggestedPlaces.first?.interests == nil)
        #expect(research.suggestedPlaces.count == 1)
    }

    @Test func theSchemaAsksForInterestsOnEverySuggestedPlace() throws {
        let schema = try JSONEncoder().encode(ResearchResult.schema())
        let text = try #require(String(data: schema, encoding: .utf8))
        #expect(text.contains(#""interests""#))
        #expect(text.contains(#""required":["name","area","kind","why","interests"]"#))
    }
}
