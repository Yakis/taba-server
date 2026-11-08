import Foundation
import PipelineKit
import ResponsesKit
import Testing

struct PipelineRequestTests {
    private let output = StructuredOutput(name: "plan", schema: .object(["type": .string("object")]))

    private func body(_ request: ResponsesRequest) throws -> [String: JSONValue] {
        try #require(JSONDecoder().decode(JSONValue.self, from: request.body()).objectValue)
    }

    @Test func initialResearchUsesPromptMetadata() throws {
        let prompt = try PromptLibrary.load("research")
        let input: JSONValue = .object(["destination": .string("Example")])
        let request = try PipelineRequestFactory.initial(prompt: prompt, input: input, model: "model",
                                                         structuredOutput: output)
        let json = try body(request)
        #expect(json["instructions"] == .string(prompt.body))
        #expect(json["model"] == .string("model"))
        #expect(json["reasoning"] == .object(["effort": .string("medium")]))
        #expect(json["tools"] == .array([.object(["type": .string("web_search")])]))
        #expect(json["include"] == .array([.string("web_search_call.action.sources")]))
        #expect(json["input"] == .array([.object(["role": .string("user"),
                                                  "content": .string(try PipelineInputBuilder.json(input))])]))
        #expect(json["store"] == .bool(false))
        #expect(json["stream"] == .bool(true))
        #expect(json["text"]?.objectValue?["format"] == .object([
            "type": .string("json_schema"), "name": .string("plan"), "strict": .bool(true),
            "schema": output.schema
        ]))
    }

    @Test func twoRepairsKeepInstructionsAndEncodeHistory() throws {
        let plan = try PromptLibrary.load("plan")
        let repair = try PromptLibrary.load("repair")
        let input: JSONValue = .object(["trip": .string("example")])
        let initial = try PipelineRequestFactory.initial(prompt: plan, input: input, model: "model",
                                                         structuredOutput: output)
        var conversation = PipelineConversation(instructions: plan.body,
                                                messages: [.init(role: .user, content: initial.userText)])
        let initialConversation = try body(conversation.request(model: "model", structuredOutput: output))
        #expect(initialConversation["instructions"] == .string(plan.body))
        #expect(initialConversation["reasoning"] == .object(["effort": .string("high")]))
        for round in 1...2 {
            conversation = conversation.appendingRepair(previousAssistant: "plan \(round)",
                                                        repairText: repair.body, payload: "{\"issues\":[]}")
            let request = try conversation.request(model: "model", structuredOutput: output)
            let json = try body(request)
            #expect(json["instructions"] == .string(plan.body))
            #expect(json["model"] == .string("model"))
            #expect(json["text"]?.objectValue?["format"]?.objectValue?["schema"] == output.schema)
            #expect(json["tools"] == nil)
            #expect(json["include"] == nil)
            #expect(repair.effort == "high")
            #expect(json["reasoning"] == .object(["effort": .string("high")]))
            #expect(conversation.messages.last?.content == repair.body + "\n\n{\"issues\":[]}")
            let expected = conversation.messages.map { message in
                JSONValue.object(["role": .string(message.role.rawValue), "content": .string(message.content)])
            }
            #expect(json["input"] == .array(expected))
        }
        let override = try body(conversation.request(model: "model", structuredOutput: output,
                                                     reasoningEffort: "low"))
        #expect(override["reasoning"] == .object(["effort": .string("low")]))
        let third = conversation.appendingRepair(previousAssistant: "plan 3", repairText: repair.body, payload: "{}")
        #expect(throws: PipelineRequestError.tooManyRepairs) {
            try third.request(model: "model", structuredOutput: output)
        }
    }

    @Test func rejectsWrongRolesAndUnsupportedTools() throws {
        let repair = try PromptLibrary.load("repair")
        #expect(throws: PipelineRequestError.invalidPromptRole("message")) {
            try PipelineRequestFactory.initial(prompt: repair, input: .object([:]), model: "m",
                                               structuredOutput: output)
        }
        let plan = try PromptLibrary.load("plan")
        #expect(throws: PipelineRequestError.inputMustBeObject) {
            try PipelineRequestFactory.initial(prompt: plan, input: .null, model: "m", structuredOutput: output)
        }
        let unknown = try PromptLibrary.parse(
            "---\nid: x\nversion: 1\nrole: instructions\noutput: X\ntools: unknown\n---\nbody"
        )
        #expect(throws: PipelineRequestError.unsupportedTool("unknown")) {
            try PipelineRequestFactory.initial(prompt: unknown, input: .object([:]), model: "m",
                                               structuredOutput: output)
        }
        let invalid = PipelineConversation(instructions: plan.body, messages: [.init(role: .assistant, content: "x")])
        #expect(throws: PipelineRequestError.invalidConversation) {
            try invalid.request(model: "m", structuredOutput: output)
        }
    }
}
