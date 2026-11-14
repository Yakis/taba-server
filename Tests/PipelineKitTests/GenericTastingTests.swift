import Foundation
import GuideKit
@testable import PipelineKit
import Testing

struct GenericTastingTests {
    @Test(arguments: ["Bread", "Cheese", "Vegetables", "Indian snacks", "Craft beer", "Fresh vegetables", "Coffee",
                      "Local bread & cheese", "Real ale", "Sweets", "Sweet", "chocolates"])
    func categoriesAreGeneric(name: String) {
        #expect(GenericTasting.isGeneric(name))
    }

    @Test(arguments: ["Parkin", "Cranachan", "Irn-Bru", "Fish and chips", "Earl Grey tea", "Pease pudding",
                      "Bread and butter pudding", "Oats", "Eccles cakes"])
    func specificNamesAreNotGeneric(name: String) {
        #expect(!GenericTasting.isGeneric(name))
    }

    @Test func aModifierAloneOrAnEmptyNameIsNotGeneric() {
        #expect(!GenericTasting.isGeneric("Local"))
        #expect(!GenericTasting.isGeneric(""))
        #expect(!GenericTasting.isGeneric("&"))
    }

    @Test func blockingFollowsTheRetryRuleForTastingKinds() {
        #expect(GuidePipeline.blocksCopy(.genericTasting("Bread"), retried: false))
        #expect(!GuidePipeline.blocksCopy(.genericTasting("Bread"), retried: true))
        #expect(GuidePipeline.blocksCopy(.tastingCount, retried: false))
        #expect(!GuidePipeline.blocksCopy(.tastingCount, retried: true))
    }

    @Test func removingGenericTastingKeepsTheSpecificItemsInOrder() throws {
        let item: (String) -> TasteItem = { TasteItem(name: $0, note: "A named dish.") }
        let copy = GuideCopy(hero: GuideHero(title: "Walks", subtitle: "A walk.", tagline: "Rest"), days: [],
                             stops: [], places: [], lists: [],
                             tasting: [item("Bread"), item("Parkin"), item("Coffee"), item("Cranachan")],
                             notes: GuideNotes(weather: "", light: "", backupPlan: "", rules: ""))
        #expect(copy.removingGenericTasting().tasting.map(\.name) == ["Parkin", "Cranachan"])
    }
}
