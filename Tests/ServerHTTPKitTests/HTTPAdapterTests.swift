import AsyncHTTPClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOHTTP1
@testable import ServerHTTPKit
import Testing

@Suite struct HTTPAdapterTests {
    @Test func splitLinesAcrossChunksAndKeepEmptySSESeparators() async throws {
        let chunks = ["data: hel", "lo\r", "\n\n", "data: end"]
        let reader = LineReader(body: .stream(chunksStream(chunks)))
        #expect(try await reader.next() == "data: hello")
        #expect(try await reader.next() == "")
        #expect(try await reader.next() == "data: end")
        #expect(try await reader.next() == nil)
    }

    @Test func rejectsOversizedLine() async throws {
        let reader = LineReader(body: .bytes(ByteBuffer(bytes: Array(repeating: UInt8(65), count: 1_048_577))))
        await #expect(throws: ServerHTTPError.lineTooLong) { try await reader.next() }
    }

    @Test func requestConversionPreservesMethodHeadersAndBody() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.com/path")))
        request.httpMethod = "POST"
        request.setValue("example", forHTTPHeaderField: "X-Test")
        request.httpBody = Data("body".utf8)
        let converted = try Adapter.request(request)
        #expect(converted.method == .POST)
        #expect(converted.headers.first(name: "X-Test") == "example")
        #expect(converted.body != nil)
    }

    @Test func responseHeadersAreCaseInsensitiveAndCombineDuplicates() {
        var headers = HTTPHeaders()
        headers.add(name: "X-Test", value: "one")
        headers.add(name: "x-test", value: "two")
        #expect(Adapter.headers(headers)["x-test"] == "one, two")
    }

    private func chunksStream(_ chunks: [String]) -> AsyncStream<ByteBuffer> {
        AsyncStream { continuation in
            for chunk in chunks { continuation.yield(ByteBuffer(string: chunk)) }
            continuation.finish()
        }
    }
}
