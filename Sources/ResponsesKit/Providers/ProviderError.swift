import Foundation

/// Why a non-ChatGPT provider could not give an answer. Messages never include a key, a token or request text.
public enum ProviderError: Error, Sendable, Equatable {
    /// The server has no key for the provider, so the model is not offered and must not be used.
    case missingKey(provider: String)
    /// The provider answered 401 or 403.
    case keyRefused(provider: String)
    /// Still 429 after the retries.
    case rateLimited(provider: String)
    /// Still 5xx or 529 after the retries.
    case unavailable(provider: String, status: Int)
    /// A 400 or other client error. `message` is the provider's own text, when it sent one.
    case rejected(provider: String, message: String?)
    /// The model stopped for a reason that gives no usable answer (refusal, token limit, and so on).
    case stopped(provider: String, reason: String)
    /// The stream reported an error event.
    case streamFailed(provider: String, type: String?)
    /// The answer could not be read, or it was incomplete.
    case malformedResponse(provider: String)
    /// No response, or a transport failure.
    case requestFailed(provider: String, status: Int?)

    /// Maps a failed DeepSeek (or other Responses-format) outcome to the same errors as the Messages client.
    public static func from(_ outcome: ResponsesOutcome, provider: String) -> ProviderError {
        switch outcome.status {
        case 401, 403: .keyRefused(provider: provider)
        case 429: .rateLimited(provider: provider)
        case let status? where status >= 500: .unavailable(provider: provider, status: status)
        default: .requestFailed(provider: provider, status: outcome.status)
        }
    }
}
