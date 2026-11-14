import PipelineKit
import ResponsesKit
@testable import ServerKit
import Testing

struct EvidenceRecordTests {
    @Test func aFailedRequestKeepsWhyItFailed() throws {
        let record = try EvidenceRecord(.pipeline(.requestFailed(step: "plan", message: "rateLimited", seconds: 1.5)))
        #expect(record.fields["event"] == .string("requestFailed"))
        #expect(record.fields["message"] == .string("rateLimited"))
    }

    @Test func aLongFailureMessageIsCut() throws {
        let long = String(repeating: "x", count: 900)
        let record = try EvidenceRecord(.pipeline(.requestFailed(step: "plan", message: long, seconds: 1)))
        #expect(record.fields["message"] == .string(String(repeating: "x", count: 500)))
    }
}
