import Foundation

/// Why an inference call failed. The two limit errors have their own cases, as the docs ask. Other structured codes
/// keep the exact `code` and `param` so the caller can apply the recovery the docs give.
public enum ResponsesError: Error, Sendable, Equatable {
    /// subscription_sharing_usage_limit_exceeded: pause plan-based requests and link to ChatGPT settings.
    case usageLimitExceeded(message: String?)
    /// subscription_sharing_usage_unavailable: usage could not be checked. Retry later with backoff.
    case usageUnavailable(message: String?)
    /// A structured Responses error with its exact code and param.
    case apiError(code: String?, param: String?, message: String?, status: Int?)
    /// The request was refused before a stream opened. Only the diagnostic `detail` text is available.
    case admissionRejected(status: Int, detail: String?)
    /// The response ended with response.incomplete.
    case incomplete(reason: String?)
    /// The stream ended without response.completed. Inference did not finish.
    case streamEndedWithoutCompletion
    /// The request never got a response.
    case transport(String)

    /// Maps a structured error. The two limit codes go to their own cases; everything else keeps its code.
    public static func structured(code: String?, param: String?, message: String?, status: Int?) -> ResponsesError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            return .usageLimitExceeded(message: message)
        case "subscription_sharing_usage_unavailable":
            return .usageUnavailable(message: message)
        default:
            return .apiError(code: code, param: param, message: message, status: status)
        }
    }

    /// Reads an error body from a refused request: `{"error": {...}}` or the admission form `{"detail": "..."}`.
    public static func fromHTTPBody(status: Int, body: String) -> ResponsesError {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)),
              let object = value.objectValue
        else {
            return .admissionRejected(status: status, detail: nil)
        }
        if let error = object["error"]?.objectValue {
            return structured(
                code: error["code"]?.stringValue,
                param: error["param"]?.stringValue,
                message: error["message"]?.stringValue,
                status: status
            )
        }
        return .admissionRejected(status: status, detail: object["detail"]?.stringValue)
    }
}
