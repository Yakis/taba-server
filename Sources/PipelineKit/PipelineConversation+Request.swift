import ResponsesKit

public enum PipelineRequestError: Error, Equatable {
    case invalidPromptRole(String)
    case unsupportedTool(String)
    case inputMustBeObject
    case invalidConversation
    case tooManyRepairs
}

/// Builds an initial request from a reviewed prompt and a JSON input object.
public enum PipelineRequestFactory {
    public static func initial(prompt: Prompt, input: JSONValue, model: String,
                               structuredOutput: StructuredOutput) throws -> ResponsesRequest {
        guard prompt.role == "instructions" else { throw PipelineRequestError.invalidPromptRole(prompt.role) }
        guard input.objectValue != nil else { throw PipelineRequestError.inputMustBeObject }
        for tool in prompt.tools where tool != "web_search" {
            throw PipelineRequestError.unsupportedTool(tool)
        }
        let search = prompt.tools.contains("web_search")
        return ResponsesRequest(model: model, instructions: prompt.body,
                                userText: try PipelineInputBuilder.json(input),
                                structuredOutput: structuredOutput, webSearch: search,
                                includeSearchSources: search, reasoningEffort: prompt.effort)
    }
}

extension PipelineConversation {
    /// Converts a plan conversation to a request. Only two complete repair rounds can be sent.
    public func request(model: String, structuredOutput: StructuredOutput,
                        reasoningEffort: String? = nil) throws -> ResponsesRequest {
        guard messages.count <= 5 else { throw PipelineRequestError.tooManyRepairs }
        guard !messages.isEmpty, messages.count % 2 == 1,
              messages.enumerated().allSatisfy({ index, message in
                  message.role == (index.isMultiple(of: 2) ? .user : .assistant)
              }) else { throw PipelineRequestError.invalidConversation }
        let input = messages.map { message in
            ResponsesMessage(role: message.role == .user ? .user : .assistant, content: message.content)
        }
        let effort: String?
        if let reasoningEffort {
            effort = reasoningEffort
        } else {
            effort = try PromptLibrary.load(messages.count > 1 ? "repair" : "plan").effort
        }
        return ResponsesRequest(model: model, instructions: instructions, messages: input,
                                structuredOutput: structuredOutput, reasoningEffort: effort)
    }
}
