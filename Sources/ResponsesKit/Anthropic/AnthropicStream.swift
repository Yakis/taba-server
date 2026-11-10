import Foundation

/// One model turn read from a Messages stream. `content` is the turn's content rebuilt as Anthropic sent it, which is
/// what a `pause_turn` continuation sends back.
public struct AnthropicTurn: Sendable, Equatable {
    public let messageID: String?
    public let stopReason: String
    public let content: [JSONValue]
    /// The text after the last tool result: the answer. Text before a search is narration and is left out.
    public let answer: String
    public let sourceURLs: [String]
    public let citationURLs: [String]
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let webSearchRequests: Int

    public init(
        messageID: String?, stopReason: String, content: [JSONValue], answer: String, sourceURLs: [String],
        citationURLs: [String], inputTokens: Int?, outputTokens: Int?, webSearchRequests: Int
    ) {
        self.messageID = messageID
        self.stopReason = stopReason
        self.content = content
        self.answer = answer
        self.sourceURLs = sourceURLs
        self.citationURLs = citationURLs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.webSearchRequests = webSearchRequests
    }
}

/// Reads the server-sent lines of one Messages response into a turn. Pure: tests feed recorded lines.
public enum AnthropicStream {
    /// The turn in the stream. Throws on an error event, a malformed event, or a stream without a stop reason.
    public static func turn(lines: [String]) throws(ProviderError) -> AnthropicTurn {
        var parser = SSEParser()
        var reader = Reader()
        for line in lines {
            if let event = parser.consume(line: line) {
                try reader.consume(event)
            }
        }
        if let event = parser.finish() {
            try reader.consume(event)
        }
        return try reader.turn()
    }

    /// The `error` object of a refused response (`{"type":"error","error":{"type":..,"message":..}}`).
    public static func errorDetails(lines: [String]) -> (type: String?, message: String?) {
        let text = lines.joined(separator: "\n")
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)),
              let error = value.objectValue?["error"]?.objectValue
        else {
            return (nil, nil)
        }
        return (error["type"]?.stringValue, error["message"]?.stringValue)
    }

    private struct Block {
        var fields: [String: JSONValue]
        var kind: String
        var text: String
        var citations: [JSONValue]
        var partialJSON = ""
    }

    private struct Reader {
        var messageID: String?
        var inputTokens: Int?
        var outputTokens: Int?
        var webSearchRequests = 0
        var stopReason: String?
        var blocks: [Block] = []
        var positions: [Int: Int] = [:]

        mutating func consume(_ event: SSEEvent) throws(ProviderError) {
            guard let object = Self.object(from: event) else { return }
            let type = object["type"]?.stringValue ?? event.name ?? ""
            switch type {
            case "message_start":
                let message = object["message"]?.objectValue
                messageID = message?["id"]?.stringValue
                inputTokens = message?["usage"]?.objectValue?["input_tokens"].flatMap(Self.integer)
            case "content_block_start":
                try start(object)
            case "content_block_delta":
                try delta(object)
            case "content_block_stop":
                try stop(object)
            case "message_delta":
                messageDelta(object)
            case "error":
                let error = object["error"]?.objectValue
                throw .streamFailed(provider: AnthropicMessages.providerName, type: error?["type"]?.stringValue)
            default:
                break
            }
        }

        func turn() throws(ProviderError) -> AnthropicTurn {
            guard let stopReason else {
                throw .malformedResponse(provider: AnthropicMessages.providerName)
            }
            return AnthropicTurn(
                messageID: messageID,
                stopReason: stopReason,
                content: blocks.map(Self.content),
                answer: answer(),
                sourceURLs: unique(blocks.flatMap(Self.sources)),
                citationURLs: unique(blocks.flatMap { $0.citations.flatMap(Self.citationURLs) }),
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                webSearchRequests: webSearchRequests
            )
        }

        private mutating func start(_ object: [String: JSONValue]) throws(ProviderError) {
            guard let index = object["index"].flatMap(Self.integer),
                  let block = object["content_block"]?.objectValue,
                  let kind = block["type"]?.stringValue
            else {
                throw .malformedResponse(provider: AnthropicMessages.providerName)
            }
            positions[index] = blocks.count
            blocks.append(Block(
                fields: block,
                kind: kind,
                text: block["text"]?.stringValue ?? "",
                citations: block["citations"]?.arrayValue ?? []
            ))
        }

        private mutating func delta(_ object: [String: JSONValue]) throws(ProviderError) {
            let position = try position(of: object)
            guard let change = object["delta"]?.objectValue else { return }
            switch change["type"]?.stringValue {
            case "text_delta":
                blocks[position].text += change["text"]?.stringValue ?? ""
            case "citations_delta":
                if let citation = change["citation"] {
                    blocks[position].citations.append(citation)
                }
            case "input_json_delta":
                blocks[position].partialJSON += change["partial_json"]?.stringValue ?? ""
            default:
                break
            }
        }

        /// A tool's input arrives as JSON text in pieces. It is read whole when the block stops.
        private mutating func stop(_ object: [String: JSONValue]) throws(ProviderError) {
            let position = try position(of: object)
            guard !blocks[position].partialJSON.isEmpty else { return }
            guard let input = try? JSONDecoder().decode(JSONValue.self, from: Data(blocks[position].partialJSON.utf8)),
                  input.objectValue != nil
            else {
                throw .malformedResponse(provider: AnthropicMessages.providerName)
            }
            blocks[position].fields["input"] = input
            blocks[position].partialJSON = ""
        }

        private mutating func messageDelta(_ object: [String: JSONValue]) {
            if let reason = object["delta"]?.objectValue?["stop_reason"]?.stringValue {
                stopReason = reason
            }
            let usage = object["usage"]?.objectValue
            if let output = usage?["output_tokens"].flatMap(Self.integer) {
                outputTokens = output
            }
            let searches = usage?["server_tool_use"]?.objectValue?["web_search_requests"].flatMap(Self.integer)
            webSearchRequests = searches ?? webSearchRequests
        }

        private func position(of object: [String: JSONValue]) throws(ProviderError) -> Int {
            guard let index = object["index"].flatMap(Self.integer), let position = positions[index] else {
                throw .malformedResponse(provider: AnthropicMessages.providerName)
            }
            return position
        }

        /// Text after the last tool result. With no tool result, all the text is the answer.
        private func answer() -> String {
            let start = blocks.lastIndex(where: { $0.kind.hasSuffix("_tool_result") }).map { $0 + 1 } ?? 0
            return blocks[start...].filter { $0.kind == "text" }.map(\.text).joined()
        }

        /// The block as the next request must send it back. Text carries its citations only when it has some.
        private static func content(_ block: Block) -> JSONValue {
            var fields = block.fields
            if block.kind == "text" {
                fields["text"] = .string(block.text)
                fields["citations"] = block.citations.isEmpty ? nil : JSONValue.array(block.citations)
            }
            return .object(fields)
        }

        private static func sources(_ block: Block) -> [String] {
            guard block.kind == "web_search_tool_result", let results = block.fields["content"]?.arrayValue else {
                return []
            }
            // A failed search comes back as an error object instead of a list, and then it has no sources.
            return results.compactMap { $0.objectValue?["url"]?.stringValue }
        }

        private static func citationURLs(_ citation: JSONValue) -> [String] {
            citation.objectValue?["url"]?.stringValue.map { [$0] } ?? []
        }

        private func unique(_ urls: [String]) -> [String] {
            var seen = Set<String>()
            return urls.filter { seen.insert($0).inserted }
        }

        private static func object(from event: SSEEvent) -> [String: JSONValue]? {
            guard event.data != "[DONE]",
                  let value = try? JSONDecoder().decode(JSONValue.self, from: Data(event.data.utf8))
            else {
                return nil
            }
            return value.objectValue
        }

        private static func integer(_ value: JSONValue) -> Int? {
            switch value {
            case .integer(let number): number
            case .number(let number): Int(number)
            default: nil
            }
        }
    }
}
