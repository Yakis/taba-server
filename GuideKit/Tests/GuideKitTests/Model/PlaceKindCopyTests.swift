import GuideKit
import Testing

struct PlaceKindCopyTests {
    @Test func lodgingLuggageAndStationsNeedNoCopy() {
        let withoutCopy = PlaceKind.allCases.filter { !$0.needsCopy }
        #expect(Set(withoutCopy) == [.lodging, .luggage, .station])
    }

    @Test func everyOtherKindNeedsCopy() {
        let withCopy = PlaceKind.allCases.filter(\.needsCopy)
        #expect(withCopy.count == PlaceKind.allCases.count - 3)
        #expect(withCopy.contains(.market))
        #expect(withCopy.contains(.viewpoint))
    }
}
