@testable import LivePipelineKit
import ResponsesKit
import ServerKit
import Testing

struct ReplayCorruptionTests {
    @Test func missingAndMalformedSourcesFailClosed() async {
        let base: [String: JSONValue] = ["event": .string("response"), "step": .string("research"),
                                         "answer": .string("{}"), "status": .string("completed")]
        for event in [base, base.merging(["sources": .string("not-an-array")]) { _, new in new }] {
            let replay = ReplayResponses(events: [event], stage: .research)
            await #expect(throws: ReplayError.self) { try await replay.next() }
        }
    }
}
