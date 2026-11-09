import Foundation
import GuideKit
import ServerKit
import Testing

struct ModelChoiceTests {
    private let plan = ["gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-6-sol", "gpt-6-astra",
                        "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]

    @Test func picksTheHighestVersionOfEachFamilyInOrder() {
        #expect(ModelChoice.options(fromSlugs: plan) == [
            ModelOption(id: "gpt-6.1-sol", name: "Sol"),
            ModelOption(id: "gpt-6.1-terra", name: "Terra"),
            ModelOption(id: "gpt-6-luna", name: "Luna")
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
        #expect(ModelChoice.option(for: "gpt-5.6-astra") == ModelOption(id: "gpt-5.6-astra", name: "Astra"))
        #expect(ModelChoice.option(for: "gpt-4o") == ModelOption(id: "gpt-4o", name: "gpt-4o"))
    }

    @Test func fixedCatalogOffersOnlyTheDefault() async {
        let catalog = FixedModelCatalog(defaultModel: "gpt-6.1-sol")
        #expect(catalog.defaultModel == "gpt-6.1-sol")
        #expect(await catalog.options() == [ModelOption(id: "gpt-6.1-sol", name: "Sol")])
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
