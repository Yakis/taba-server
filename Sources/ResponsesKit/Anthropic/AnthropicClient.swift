import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends a `ResponsesRequest` to the Anthropic Messages API and returns the answer in the same shape the pipeline
/// reads from ChatGPT. Retries rate limits and overloads, follows `pause_turn`, and retries once without the schema
/// when Anthropic refuses the schema format while web search is on.
public struct AnthropicClient: Sendable {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    /// The waits before the first and second retry. A `retry-after` header replaces them, capped at 60 seconds.
    static let retryWaits: [Duration] = [.seconds(10), .seconds(30)]
    static let maxRetryAfter = 60
    static let maxContinuations = 3

    private let transport: any StreamTransport
    private let apiKey: String
    private let sleep: Sleep

    /// The key is sent only in the `x-api-key` header. It never appears in an error.
    public init(transport: any StreamTransport, apiKey: String,
                sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.apiKey = apiKey
        self.sleep = sleep
    }

    public func send(_ request: ResponsesRequest) async throws -> ResponsesResult {
        do {
            return try await run(request, options: AnthropicMessages.Options())
        } catch ProviderError.rejected(_, let message) where Self.rejectsSchema(request, message: message) {
            guard let output = request.structuredOutput else {
                throw ProviderError.malformedResponse(provider: AnthropicMessages.providerName)
            }
            let schema = try JSONEncoder().encode(output.schema)
            let instruction = "Reply with only one JSON object that matches this JSON Schema, with no other text:\n"
                + (String(bytes: schema, encoding: .utf8) ?? "")
            let options = AnthropicMessages.Options(includeFormat: false, systemSuffix: instruction)
            let result = try await run(request, options: options)
            return ResponsesResult(
                text: try Self.jsonObject(in: result.text),
                status: result.status,
                responseId: result.responseId,
                usage: result.usage,
                webSearchCount: result.webSearchCount,
                sourceURLs: result.sourceURLs,
                citationURLs: result.citationURLs
            )
        }
    }

    /// True when a 400 is about the schema format, which the retry without `format` can avoid.
    static func rejectsSchema(_ request: ResponsesRequest, message: String?) -> Bool {
        guard request.webSearch, request.structuredOutput != nil, let message = message?.lowercased() else {
            return false
        }
        return message.contains("citation") || message.contains("output_config") || message.contains("format")
    }

    /// The text from the first `{` to the last `}`. Throws when there is no object in it.
    static func jsonObject(in text: String) throws -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
            throw ProviderError.malformedResponse(provider: AnthropicMessages.providerName)
        }
        return String(text[start...end])
    }

    /// Follows `pause_turn` up to three times, sending the paused content back each time, and merges the turns.
    private func run(_ request: ResponsesRequest, options: AnthropicMessages.Options) async throws -> ResponsesResult {
        var options = options
        var turns: [AnthropicTurn] = []
        var pausedContent: [JSONValue] = []
        while true {
            let body = try AnthropicMessages.body(for: request, options: options)
            let turn = try await postTurn(body)
            turns.append(turn)
            switch turn.stopReason {
            case "end_turn":
                return Self.result(turns)
            case "pause_turn" where turns.count <= Self.maxContinuations:
                // Every paused turn goes back in one assistant message, never two assistant messages in a row.
                pausedContent += turn.content
                options.continuation = [.object(["role": .string("assistant"), "content": .array(pausedContent)])]
            default:
                throw ProviderError.stopped(provider: AnthropicMessages.providerName, reason: turn.stopReason)
            }
        }
    }

    /// One request, with the retries for rate limits and server errors.
    private func postTurn(_ body: Data) async throws -> AnthropicTurn {
        var retries = 0
        while true {
            let response = try await openStream(body)
            let lines = try await read(response)
            switch response.status {
            case 200..<300:
                return try AnthropicStream.turn(lines: lines)
            case 401, 403:
                throw ProviderError.keyRefused(provider: AnthropicMessages.providerName)
            case 429, 500...599:
                guard retries < Self.retryWaits.count else {
                    if response.status == 429 {
                        throw ProviderError.rateLimited(provider: AnthropicMessages.providerName)
                    }
                    throw ProviderError.unavailable(provider: AnthropicMessages.providerName, status: response.status)
                }
                try await sleep(Self.wait(after: response.headers, retry: retries))
                retries += 1
            default:
                let details = AnthropicStream.errorDetails(lines: lines)
                throw ProviderError.rejected(provider: AnthropicMessages.providerName, message: details.message)
            }
        }
    }

    private func openStream(_ body: Data) async throws -> StreamResponse {
        guard let url = URL(string: AnthropicMessages.endpoint) else {
            throw ProviderError.requestFailed(provider: AnthropicMessages.providerName, status: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AnthropicMessages.version, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(AnthropicMessages.beta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = body
        do {
            return try await transport.stream(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProviderError.requestFailed(provider: AnthropicMessages.providerName, status: nil)
        }
    }

    private func read(_ response: StreamResponse) async throws -> [String] {
        var lines: [String] = []
        do {
            for try await line in response.lines {
                lines.append(line)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ProviderError.requestFailed(provider: AnthropicMessages.providerName, status: response.status)
        }
        return lines
    }

    /// The wait before a retry: the `retry-after` seconds when the header is a whole number, capped, else the schedule.
    static func wait(after headers: [String: String], retry: Int) -> Duration {
        if let raw = headers["retry-after"], let seconds = Int(raw.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
            return .seconds(min(seconds, maxRetryAfter))
        }
        return retryWaits[min(retry, retryWaits.count - 1)]
    }

    /// Joins the turns into one result. The answer is the last turn's; sources and citations are kept from every turn.
    static func result(_ turns: [AnthropicTurn]) -> ResponsesResult {
        let last = turns[turns.count - 1]
        let inputs = turns.compactMap(\.inputTokens)
        let outputs = turns.compactMap(\.outputTokens)
        let input = inputs.isEmpty ? nil : inputs.reduce(0, +)
        let output = outputs.isEmpty ? nil : outputs.reduce(0, +)
        let usage = input == nil && output == nil ? nil : ResponsesUsage(
            inputTokens: input, outputTokens: output, totalTokens: (input ?? 0) + (output ?? 0)
        )
        return ResponsesResult(
            text: last.answer,
            status: "completed",
            responseId: last.messageID,
            usage: usage,
            webSearchCount: turns.reduce(0) { $0 + $1.webSearchRequests },
            sourceURLs: unique(turns.flatMap(\.sourceURLs)),
            citationURLs: unique(turns.flatMap(\.citationURLs))
        )
    }

    private static func unique(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }
}
