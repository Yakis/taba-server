import Foundation
import ResponsesKit

/// Returns canned responses, and records the requests it saw. Tests use this in place of the network.
final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) -> (Int, Data)
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = handler(request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            throw TransportError.notHTTP
        }
        return (body, response)
    }
}

/// Streams recorded lines, as if they came from the Responses API.
struct FakeStreamTransport: StreamTransport {
    let status: Int
    let lines: [String]

    func stream(for request: URLRequest) async throws -> StreamResponse {
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        for line in lines {
            continuation.yield(line)
        }
        continuation.finish()
        return StreamResponse(status: status, lines: stream)
    }
}

/// A temporary folder for file tests, removed when the test ends.
struct TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("taba-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
