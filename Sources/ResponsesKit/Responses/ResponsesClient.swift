import Foundation

/// The status and body lines of a streamed response. Tests replace the transport with recorded lines.
public struct StreamResponse: Sendable {
    public let status: Int
    public let lines: AsyncThrowingStream<String, any Error>

    public init(status: Int, lines: AsyncThrowingStream<String, any Error>) {
        self.status = status
        self.lines = lines
    }
}

public protocol StreamTransport: Sendable {
    func stream(for request: URLRequest) async throws -> StreamResponse
}

/// The production transport, on URLSession. Body lines are read as they arrive.
public struct URLSessionStreamTransport: StreamTransport {
    public init() {}

    public func stream(for request: URLRequest) async throws -> StreamResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TransportError.notHTTP
        }
        let (lines, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let reader = Task {
            do {
                // Not `bytes.lines`: it drops empty lines, and empty lines are what end each SSE event.
                try await StreamLines.split(bytes) { continuation.yield($0) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in reader.cancel() }
        return StreamResponse(status: http.statusCode, lines: lines)
    }
}

/// What one inference call produced. `rawBody` is the response body only, never headers.
public struct ResponsesOutcome: Sendable, Equatable {
    public let result: ResponsesResult?
    public let error: ResponsesError?
    public let rawBody: String
    public let status: Int?

    public init(result: ResponsesResult?, error: ResponsesError?, rawBody: String, status: Int?) {
        self.result = result
        self.error = error
        self.rawBody = rawBody
        self.status = status
    }
}

/// Sends a Responses request to the ChatGPT plan route and reads the stream to its end.
public struct ResponsesClient: Sendable {
    public static let endpoint = "https://api.openai.com/v1/responses"

    private let transport: any StreamTransport

    public init(transport: any StreamTransport = URLSessionStreamTransport()) {
        self.transport = transport
    }

    /// POSTs `body` with the bearer access token. The token is set on the request only, never logged.
    public func send(body: Data, accessToken: String) async -> ResponsesOutcome {
        guard let url = URL(string: Self.endpoint) else {
            return ResponsesOutcome(result: nil, error: .transport("bad endpoint"), rawBody: "", status: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = body
        do {
            let response = try await transport.stream(for: request)
            var lines: [String] = []
            for try await line in response.lines {
                lines.append(line)
            }
            let raw = lines.joined(separator: "\n")
            guard (200..<300).contains(response.status) else {
                let error = ResponsesError.fromHTTPBody(status: response.status, body: raw)
                return ResponsesOutcome(result: nil, error: error, rawBody: raw, status: response.status)
            }
            return Self.accumulate(lines: lines, raw: raw, status: response.status)
        } catch {
            return ResponsesOutcome(
                result: nil,
                error: .transport(error.localizedDescription),
                rawBody: "",
                status: nil
            )
        }
    }

    static func accumulate(lines: [String], raw: String, status: Int) -> ResponsesOutcome {
        var parser = SSEParser()
        var accumulator = ResponsesAccumulator()
        do {
            for line in lines {
                if let event = parser.consume(line: line) {
                    try accumulator.consume(event)
                }
            }
            if let event = parser.finish() {
                try accumulator.consume(event)
            }
            let result = try accumulator.result()
            return ResponsesOutcome(result: result, error: nil, rawBody: raw, status: status)
        } catch {
            return ResponsesOutcome(result: nil, error: Self.responsesError(error), rawBody: raw, status: status)
        }
    }

    private static func responsesError(_ error: any Error) -> ResponsesError {
        (error as? ResponsesError) ?? .transport("unexpected error")
    }
}
