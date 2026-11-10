import PipelineKit
import Testing

struct PromptLibraryTests {
    @Test(arguments: ["plan", "repair", "research", "ticket", "write"])
    func realPrompts(id: String) throws {
        let prompt = try PromptLibrary.load(id)
        #expect(prompt.id == id)
        let versions = ["plan": 5, "repair": 2, "research": 2, "write": 4]
        #expect(prompt.version == (versions[id] ?? 1))
        #expect(prompt.body.isEmpty == false)
        #expect(prompt.body.hasPrefix("---") == false)
        #expect(prompt.role == (id == "repair" ? "message" : "instructions"))
    }

    @Test func optionalFields() throws {
        let ticket = try PromptLibrary.load("ticket")
        let research = try PromptLibrary.load("research")
        #expect(ticket.effort == nil)
        #expect(ticket.tools.isEmpty)
        #expect(research.effort == "medium")
        #expect(research.tools == ["web_search"])
    }

    @Test func rejectsAmbiguousFrontMatter() {
        #expect(throws: PromptError.missingFrontMatter) { try PromptLibrary.parse("body") }
        #expect(throws: PromptError.duplicateField("id")) {
            try PromptLibrary.parse("---\nid: x\nid: y\n---\nbody")
        }
        #expect(throws: PromptError.invalidVersion("zero")) {
            try PromptLibrary.parse("---\nid: x\nversion: zero\nrole: instructions\noutput: X\n---\nbody")
        }
        #expect(throws: PromptError.missingField("output")) {
            try PromptLibrary.parse("---\nid: x\nversion: 1\nrole: message\n---\nbody")
        }
        #expect(throws: PromptError.missingResource("../plan")) { try PromptLibrary.load("../plan") }
    }

    @Test func supportsCRLFAndColonsInValues() throws {
        let prompt = try PromptLibrary.parse(
            "---\r\nid: x\r\nversion: 2\r\nrole: message\r\noutput: X\r\nnote: a: b\r\n---\r\n\r\nBody\r\n"
        )
        #expect(prompt.metadata["note"] == "a: b")
        #expect(prompt.body == "Body\n")
    }
}
