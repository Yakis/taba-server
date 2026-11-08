@testable import ResponsesKit
import Testing

struct StreamLinesTests {
    private func lines(of text: String) async throws -> [String] {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in Array(text.utf8) {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        var result: [String] = []
        try await StreamLines.split(bytes) { result.append($0) }
        return result
    }

    @Test func keepsEmptyLinesBetweenEvents() async throws {
        let text = "event: a\ndata: {\"n\":1}\n\nevent: b\ndata: {\"n\":2}\n\n"
        #expect(try await lines(of: text) == ["event: a", "data: {\"n\":1}", "", "event: b", "data: {\"n\":2}", ""])
    }

    @Test func removesCarriageReturns() async throws {
        #expect(try await lines(of: "data: x\r\n\r\n") == ["data: x", ""])
    }

    @Test func deliversFinalLineWithoutNewline() async throws {
        #expect(try await lines(of: "data: last") == ["data: last"])
    }

    @Test func splitLinesParseIntoSeparateEvents() async throws {
        let text = "event: response.created\ndata: {\"type\":\"response.created\"}\n\n"
            + "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n"
        var parser = SSEParser()
        var names: [String?] = []
        for line in try await lines(of: text) {
            if let event = parser.consume(line: line) {
                names.append(event.name)
            }
        }
        if let event = parser.finish() {
            names.append(event.name)
        }
        #expect(names == ["response.created", "response.completed"])
    }
}
