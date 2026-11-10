@testable import LivePipelineKit
import ServerKit
import Testing

struct ProviderRoutingTests {
    @Test func eachModelGoesToItsProvider() {
        #expect(ProviderRouting.destination(model: "gpt-6.1-terra", webSearch: true)
            == ProviderDestination(provider: .chatGPT, model: "gpt-6.1-terra"))
        #expect(ProviderRouting.destination(model: "claude-opus-5-5", webSearch: true)
            == ProviderDestination(provider: .claude, model: "claude-opus-5-5"))
        #expect(ProviderRouting.destination(model: "deepseek-v4-pro", webSearch: true)
            == ProviderDestination(provider: .deepSeek, model: "deepseek-v4-pro"))
        #expect(ProviderRouting.destination(model: "llama-3", webSearch: false) == nil)
    }

    @Test func deepSeekFlashSearchesWithV4ProAndEverythingElseKeepsFlash() {
        #expect(ProviderRouting.destination(model: "deepseek-flash", webSearch: true)
            == ProviderDestination(provider: .deepSeek, model: "deepseek-v4-pro"))
        #expect(ProviderRouting.destination(model: "deepseek-flash", webSearch: false)
            == ProviderDestination(provider: .deepSeek, model: "deepseek-flash"))
    }

    @Test func anEmptyKeyIsTheSameAsNoKey() {
        let keys = ProviderKeys(anthropic: "", deepSeek: nil)
        #expect(keys.anthropic == nil)
        #expect(keys.deepSeek == nil)
        #expect(keys.fixedOptions.isEmpty)
    }

    @Test func aModelIsServedOnlyWhenItsKeyIsSet() {
        let keys = ProviderKeys(anthropic: "anthropic-key-not-real-0001", deepSeek: nil)
        #expect(keys.canServe("claude-opus-5-5"))
        #expect(!keys.canServe("deepseek-flash"))
        #expect(keys.canServe("gpt-6.1-sol"))
        #expect(!keys.canServe("llama-3"))
        #expect(keys.fixedOptions.map(\.id) == ["claude-opus-5-5", "claude-sonnet-5-5"])
    }

    @Test func bothKeysOfferBothProvidersInOrder() {
        let keys = ProviderKeys(anthropic: "anthropic-key-not-real-0001", deepSeek: "deepseek-key-not-real-0001")
        #expect(keys.fixedOptions.map(\.provider) == ["Claude", "Claude", "DeepSeek", "DeepSeek"])
        #expect(keys.canServe("deepseek-v4-pro"))
    }
}
