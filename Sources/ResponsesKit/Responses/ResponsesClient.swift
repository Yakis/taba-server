import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The status, header and body lines of a streamed response. Tests replace the transport with recorded lines.
/// Header names are lower case. Only `retry-after` is read from them.
public struct StreamResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let lines: AsyncThrowingStream<String, any Error>

    public init(status: Int, lines: AsyncThrowingStream<String, any Error>, headers: [String: String] = [:]) {
        self.status = status
        self.headers = headers
        self.lines = lines
    }
}

public protocol StreamTransport: Sendable {
    func stream(for request: URLRequest) async throws -> StreamResponse
}

#if !os(Linux)
/// The production transport, on URLSession. Body lines are read as they arrive.
public struct URLSessionStreamTransport: StreamTransport {
    public init() {}

    public func stream(for request: URLRequest) async throws -> StreamResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TransportError.notHTTP
        }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String {
                headers[name.lowercased()] = value
            }
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
        return StreamResponse(status: http.statusCode, lines: lines, headers: headers)
    }
}
#else
/// Linux requires an injected streaming transport; URLSession has no streaming bytes API there.
public struct URLSessionStreamTransport: StreamTransport {
    public enum Unavailable: Error { case injectStreamingTransport }

    public init() {}

    public func stream(for request: URLRequest) async throws -> StreamResponse {
        throw Unavailable.injectStreamingTransport
    }
}
#endif

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

/// Where a Responses-format request is sent, and how the key is attached. The ChatGPT plan route and DeepSeek use
/// the same format; they differ in the URL, the key header and whether sources must be recovered.
public struct ResponsesEndpoint: Sendable, Equatable {
    public let url: String
    /// The header that carries the key, and the text before the key in it.
    public let authorizationHeader: String
    public let authorizationPrefix: String
    /// DeepSeek omits `web_search_call.action.sources`. When a search returns none, the citation URLs and the URLs
    /// in the search items stand in, so research findings can still be checked against them.
    public let recoversSourceURLs: Bool

    public init(url: String, authorizationHeader: String, authorizationPrefix: String, recoversSourceURLs: Bool) {
        self.url = url
        self.authorizationHeader = authorizationHeader
        self.authorizationPrefix = authorizationPrefix
        self.recoversSourceURLs = recoversSourceURLs
    }

    public static let chatGPT = ResponsesEndpoint(
        url: ResponsesClient.endpoint, authorizationHeader: "Authorization", authorizationPrefix: "Bearer ",
        recoversSourceURLs: false
    )

    public static let deepSeek = ResponsesEndpoint(
        url: "https://api.deepseek.com/responses", authorizationHeader: "Authorization",
        authorizationPrefix: "Bearer ", recoversSourceURLs: true
    )
}

/// Sends a Responses request and reads the stream to its end. The ChatGPT plan route is the default.
public struct ResponsesClient: Sendable {
    public static let endpoint = "https://api.openai.com/v1/responses"

    private let transport: any StreamTransport
    private let endpoint: ResponsesEndpoint

    public init(transport: any StreamTransport = URLSessionStreamTransport(), endpoint: ResponsesEndpoint = .chatGPT) {
        self.transport = transport
        self.endpoint = endpoint
    }

    /// POSTs `body` with the key in the endpoint's header. The key is set on the request only, never logged.
    public func send(body: Data, accessToken: String) async -> ResponsesOutcome {
        guard let url = URL(string: endpoint.url) else {
            return ResponsesOutcome(result: nil, error: .transport("bad endpoint"), rawBody: "", status: nil)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(endpoint.authorizationPrefix + accessToken, forHTTPHeaderField: endpoint.authorizationHeader)
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
            return Self.accumulate(lines: lines, raw: raw, status: response.status,
                                   recoversSourceURLs: endpoint.recoversSourceURLs)
        } catch {
            return ResponsesOutcome(
                result: nil,
                error: .transport(error.localizedDescription),
                rawBody: "",
                status: nil
            )
        }
    }

    static func accumulate(lines: [String], raw: String, status: Int, recoversSourceURLs: Bool = false)
        -> ResponsesOutcome {
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
            let result = try accumulator.result(recoveringSourceURLs: recoversSourceURLs)
            return ResponsesOutcome(result: result, error: nil, rawBody: raw, status: status)
        } catch {
            return ResponsesOutcome(result: nil, error: Self.responsesError(error), rawBody: raw, status: status)
        }
    }

    private static func responsesError(_ error: any Error) -> ResponsesError {
        (error as? ResponsesError) ?? .transport("unexpected error")
    }
}
