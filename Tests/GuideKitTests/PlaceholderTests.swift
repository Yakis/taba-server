import GuideKit
import Testing

@Test func testTargetLinksGuideKit() {
    let name = String(describing: GuideKit.self)
    #expect(name == "GuideKit")
}
