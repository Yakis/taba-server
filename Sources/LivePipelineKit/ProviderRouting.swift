import ResponsesKit
import ServerKit

/// The provider keys the server was started with. An empty key counts as absent, and that provider is not offered.
public struct ProviderKeys: Sendable, Equatable {
    public let anthropic: String?
    public let deepSeek: String?

    public init(anthropic: String?, deepSeek: String?) {
        self.anthropic = anthropic.flatMap { $0.isEmpty ? nil : $0 }
        self.deepSeek = deepSeek.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The Claude and DeepSeek models whose keys are set. ChatGPT is not listed here: it has no key, only a sign-in.
    public var fixedOptions: [ModelOption] {
        ModelChoice.fixedOptions(anthropic: anthropic != nil, deepSeek: deepSeek != nil)
    }

    /// False for a Claude or DeepSeek model whose key is missing. ChatGPT models are assumed here, because their
    /// sign-in is checked when a request is sent.
    public func canServe(_ model: String) -> Bool {
        switch ModelProvider.of(model) {
        case .chatGPT: true
        case .claude: anthropic != nil
        case .deepSeek: deepSeek != nil
        case nil: false
        }
    }
}

/// Where one request goes: the provider that runs the model, and the model id that provider receives.
public struct ProviderDestination: Sendable, Equatable {
    public let provider: ModelProvider
    public let model: String

    public init(provider: ModelProvider, model: String) {
        self.provider = provider
        self.model = model
    }
}

public enum ProviderRouting {
    /// DeepSeek Flash cannot search. A Flash request that needs web search is sent to V4 Pro instead.
    public static let searchingFlashModel = "deepseek-v4-pro"

    /// The provider for `model`, or nil when no provider runs that id.
    public static func destination(model: String, webSearch: Bool) -> ProviderDestination? {
        guard let provider = ModelProvider.of(model) else { return nil }
        if provider == .deepSeek, model == "deepseek-flash", webSearch {
            return ProviderDestination(provider: provider, model: searchingFlashModel)
        }
        return ProviderDestination(provider: provider, model: model)
    }
}
