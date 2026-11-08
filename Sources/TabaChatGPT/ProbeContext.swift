import Foundation
import ResponsesKit

/// Counts requests across the probe. Routine and forced refreshes count too.
actor ProbeBudget {
    private var spent = 0
    let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func spend() -> Bool {
        guard spent < limit else { return false }
        spent += 1
        return true
    }

    var count: Int {
        spent
    }
}

/// One check's outcome, as written to the report.
struct ProbeRecord {
    let key: String
    let title: String
    let line: String
    let detail: [String]
    let rawBody: String?

    static func skipped(key: String, title: String, reason: String) -> ProbeRecord {
        ProbeRecord(key: key, title: title, line: reason, detail: [], rawBody: nil)
    }
}

/// What every check needs: the saved session, the client, the store, and the request budget.
struct ProbeContext: Sendable {
    let model: String
    let session: CredentialSession
    let client: ResponsesClient
    let store: CredentialStore
    let budget: ProbeBudget

    /// One inference call. It spends budget first, and a refresh near expiry spends one more.
    func inference(key: String, title: String, request: ResponsesRequest) async -> ProbeRecord {
        let current = (try? store.load())?.credentials
        if current?.needsRefresh(now: Date()) == true {
            guard await budget.spend() else {
                return .skipped(key: key, title: title, reason: "not sent: request limit reached")
            }
        }
        guard await budget.spend() else {
            return .skipped(key: key, title: title, reason: "not sent: request limit reached")
        }
        guard let body = try? request.body() else {
            return .skipped(key: key, title: title, reason: "could not build the body")
        }
        let credentials: ChatGPTCredentials
        do {
            credentials = try await session.credentials()
        } catch {
            return .skipped(key: key, title: title, reason: "not sent: \(ProbeDescribe.error(error))")
        }
        let started = ContinuousClock.now
        let outcome = await client.send(body: body, accessToken: credentials.accessToken)
        let seconds = started.duration(to: .now).components.seconds
        if let result = outcome.result {
            let usage = result.usage.map { "in \($0.inputTokens ?? 0), out \($0.outputTokens ?? 0)" } ?? "no usage"
            let line = "ok, model \(request.model), \(seconds) s, \(usage), status \(result.status ?? "-")"
            return ProbeRecord(key: key, title: title, line: line, detail: [], rawBody: outcome.rawBody)
        }
        let error = outcome.error.map(ProbeDescribe.responsesError) ?? "unknown error"
        return ProbeRecord(key: key, title: title, line: "error: \(error)", detail: [], rawBody: outcome.rawBody)
    }
}

/// Short, secret-free descriptions of errors for the terminal and the report.
enum ProbeDescribe {
    static func error(_ error: any Error) -> String {
        switch error {
        case let error as ResponsesError:
            return responsesError(error)
        case let error as OAuthTokenError:
            return "HTTP \(error.status), \(error.code ?? "no code")"
        default:
            return "\(error)"
        }
    }

    static func responsesError(_ error: ResponsesError) -> String {
        switch error {
        case .usageLimitExceeded(let message):
            return "subscription_sharing_usage_limit_exceeded \(message ?? "")"
        case .usageUnavailable(let message):
            return "subscription_sharing_usage_unavailable \(message ?? "")"
        case .apiError(let code, let param, let message, let status):
            let statusText = status.map { "HTTP \($0) " } ?? ""
            let paramText = param.map { " (param \($0))" } ?? ""
            return "\(statusText)\(code ?? "no code")\(paramText) \(message ?? "")"
        case .admissionRejected(let status, let detail):
            return "HTTP \(status) \(detail ?? "refused before the stream opened")"
        case .incomplete(let reason):
            return "incomplete \(reason ?? "")"
        case .streamEndedWithoutCompletion:
            return "the stream ended without response.completed"
        case .transport(let text):
            return "network: \(text)"
        }
    }
}
