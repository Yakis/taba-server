@testable import LivePipelineKit
import ResponsesKit
import Testing

@Suite struct ChatGPTFailureTests {
    @Test func aRefusedRequestKeepsItsStatusAndReason() {
        let outcome = ResponsesOutcome(result: nil, error: .usageLimitExceeded(message: "limit reached"),
                                       rawBody: "", status: 429)
        guard case .chatGPTFailed(let status, let reason) = LiveStageError.chatGPTFailure(outcome) else {
            Issue.record("expected chatGPTFailed")
            return
        }
        #expect(status == 429)
        #expect(reason.contains("usageLimitExceeded"))
        #expect(reason.contains("limit reached"))
    }

    @Test func anOutcomeWithNoErrorSaysNoResult() {
        let outcome = ResponsesOutcome(result: nil, error: nil, rawBody: "", status: nil)
        guard case .chatGPTFailed(let status, let reason) = LiveStageError.chatGPTFailure(outcome) else {
            Issue.record("expected chatGPTFailed")
            return
        }
        #expect(status == nil)
        #expect(reason == "no result")
    }

    @Test func aLongReasonIsCut() {
        let outcome = ResponsesOutcome(result: nil, error: .transport(String(repeating: "x", count: 1000)),
                                       rawBody: "", status: nil)
        guard case .chatGPTFailed(_, let reason) = LiveStageError.chatGPTFailure(outcome) else {
            Issue.record("expected chatGPTFailed")
            return
        }
        #expect(reason.count == 300)
    }
}
