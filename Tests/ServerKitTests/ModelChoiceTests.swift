import Foundation
import GuideKit
import ServerKit
import Testing

struct ModelChoiceTests {
    private let plan = ["gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-6-sol", "gpt-6-astra",
                        "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]

    @Test func picksTheHighestVersionOfEachFamilyInOrder() {
        #expect(ModelChoice.options(fromSlugs: plan) == [
            ModelOption(id: "gpt-6.1-sol", name: "Sol", provider: "ChatGPT"),
            ModelOption(id: "gpt-6.1-terra", name: "Terra", provider: "ChatGPT"),
            ModelOption(id: "gpt-6-luna", name: "Luna", provider: "ChatGPT")
        ])
    }

    @Test func comparesVersionsNumberByNumber() {
        #expect(ModelChoice.options(fromSlugs: ["gpt-6.9-sol", "gpt-6.10-sol"]).map(\.id) == ["gpt-6.10-sol"])
        #expect(ModelChoice.options(fromSlugs: ["gpt-6-sol", "gpt-6.0.1-sol"]).map(\.id) == ["gpt-6.0.1-sol"])
        #expect(ModelChoice.options(fromSlugs: ["gpt-5.6-sol", "gpt-6-sol"]).map(\.id) == ["gpt-6-sol"])
    }

    @Test func matchesOnlyTheExactShape() {
        let slugs = ["gpt-6.1-sol-mini", "gpt-6.1-astra", "gpt-sol", "gpt-6.1-solx", "gpt-.1-sol",
                     "gpt-6..1-sol", "gpt-6.1.-sol", "gpt-6.1-SOL", "gpt-6.1-sol"]
        #expect(ModelChoice.options(fromSlugs: slugs).map(\.id) == ["gpt-6.1-sol"])
    }

    @Test func leavesOutAFamilyWithNoSlugAndHandlesEmptyInput() {
        #expect(ModelChoice.options(fromSlugs: ["gpt-6-sol"]).map(\.id) == ["gpt-6-sol"])
        #expect(ModelChoice.options(fromSlugs: []).isEmpty)
    }

    @Test func recognisesTheOfferedShapeForInputs() {
        for slug in ["gpt-6.1-sol", "gpt-6-terra", "gpt-5.6-luna"] {
            #expect(ModelChoice.isWellFormed(slug))
        }
        for slug in ["", "gpt-sol", "gpt-6.1-astra", "gpt-6.1-sol-mini", "gpt-6.1-SOL", "gpt-6..1-sol",
                     "gpt-6.x-sol", "gpt-4o", "gpt-6.1-sol\n"] {
            #expect(!ModelChoice.isWellFormed(slug))
        }
    }

    @Test func namesAnyOptionFromItsFamilyOrSlug() {
        #expect(ModelChoice.option(for: "gpt-5.6-astra")
            == ModelOption(id: "gpt-5.6-astra", name: "Astra", provider: "ChatGPT"))
        #expect(ModelChoice.option(for: "gpt-4o") == ModelOption(id: "gpt-4o", name: "gpt-4o", provider: "ChatGPT"))
    }

    @Test func fixedCatalogOffersOnlyTheDefault() async {
        let catalog = FixedModelCatalog(defaultModel: "gpt-6.1-sol")
        #expect(catalog.defaultModel == "gpt-6.1-sol")
        #expect(await catalog.options() == [ModelOption(id: "gpt-6.1-sol", name: "Sol", provider: "ChatGPT")])
    }
}

struct TripModelInputTests {
    private let start = LocalDate("2025-11-23")!
    private let end = LocalDate("2025-11-25")!

    @Test func acceptsAWellFormedModelAndRoundTrips() throws {
        let input = try TripBuildInput(destination: "Edinburgh", from: start, to: end, model: "gpt-6.1-terra")
        let decoded = try JSONDecoder().decode(TripBuildInput.self, from: JSONEncoder().encode(input))
        #expect(decoded.model == "gpt-6.1-terra")
    }

    @Test func rejectsAMalformedModel() throws {
        #expect(throws: TripBuildInput.ValidationError.invalidModel) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, model: "gpt-6.1-astra")
        }
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","model":"gpt-4o"}"#
        #expect(throws: TripBuildInput.ValidationError.invalidModel) {
            try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        }
    }

    @Test func decodesTheModelFromJSON() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","model":"gpt-6-luna"}"#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.model == "gpt-6-luna")
    }

    @Test func oldInputWithoutAModelDecodesAsNil() throws {
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25"}"#
        let input = try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8))
        #expect(input.model == nil)
        let encoded = try String(data: JSONEncoder().encode(input), encoding: .utf8) ?? ""
        #expect(!encoded.contains("model"))
    }
}

struct ProviderModelTests {
    private let start = LocalDate("2025-11-23")!
    private let end = LocalDate("2025-11-25")!

    @Test func theProviderFollowsFromTheIdAlone() {
        #expect(ModelProvider.of("gpt-6.1-terra") == .chatGPT)
        #expect(ModelProvider.of("claude-opus-5-5") == .claude)
        #expect(ModelProvider.of("deepseek-flash") == .deepSeek)
        #expect(ModelProvider.of("gemini-2") == nil)
        #expect(ModelChoice.option(for: "gemini-2").provider == "Other")
    }

    @Test func claudeAndDeepSeekIdsAreNamedFromTheFixedList() {
        #expect(ModelChoice.option(for: "claude-opus-5-5")
            == ModelOption(id: "claude-opus-5-5", name: "Claude Opus 5.5", provider: "Claude"))
        #expect(ModelChoice.option(for: "deepseek-v4-pro")
            == ModelOption(id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", provider: "DeepSeek"))
        #expect(ModelChoice.option(for: "claude-haiku-5-0")
            == ModelOption(id: "claude-haiku-5-0", name: "claude-haiku-5-0", provider: "Claude"))
    }

    @Test func fixedOptionsDependOnEachKey() {
        #expect(ModelChoice.fixedOptions(anthropic: false, deepSeek: false).isEmpty)
        #expect(ModelChoice.fixedOptions(anthropic: true, deepSeek: false).map(\.id)
            == ["claude-opus-5-5", "claude-sonnet-5-5"])
        #expect(ModelChoice.fixedOptions(anthropic: false, deepSeek: true).map(\.id)
            == ["deepseek-v4-pro", "deepseek-flash"])
        #expect(ModelChoice.fixedOptions(anthropic: true, deepSeek: true).map(\.id)
            == ["claude-opus-5-5", "claude-sonnet-5-5", "deepseek-v4-pro", "deepseek-flash"])
    }

    @Test func claudeAndDeepSeekIdsHaveAWellFormedShape() {
        for slug in ["claude-opus-5-5", "claude-sonnet-5-5", "deepseek-flash", "deepseek-v4-pro", "claude-x.1"] {
            #expect(ModelChoice.isWellFormed(slug), "\(slug) should be accepted")
        }
        let longest = "claude-" + String(repeating: "a", count: 57)
        #expect(longest.utf8.count == 64 && ModelChoice.isWellFormed(longest))
        let tooLong = "claude-" + String(repeating: "a", count: 58)
        for slug in ["claude-Opus-5", "claude-opus 5", "claude-opus_5", "deepseek-flash\n", "claude-é",
                     "claude-opus/5", tooLong, "gemini-2"] {
            #expect(!ModelChoice.isWellFormed(slug), "\(slug) should be refused")
        }
    }

    @Test func aTripMayNameAClaudeOrDeepSeekModel() throws {
        let claude = try TripBuildInput(destination: "Edinburgh", from: start, to: end, model: "claude-opus-5-5")
        #expect(claude.model == "claude-opus-5-5")
        let json = #"{"destination":"Edinburgh","from":"2025-11-23","to":"2025-11-25","model":"deepseek-flash"}"#
        #expect(try JSONDecoder().decode(TripBuildInput.self, from: Data(json.utf8)).model == "deepseek-flash")
    }

    @Test func aTripStillRefusesAModelOfNoKnownShape() throws {
        #expect(throws: TripBuildInput.ValidationError.invalidModel) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, model: "claude-Opus")
        }
        #expect(throws: TripBuildInput.ValidationError.invalidModel) {
            try TripBuildInput(destination: "Edinburgh", from: start, to: end, model: "gemini-2.5-pro")
        }
    }
}
