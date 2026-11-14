import Foundation
import GuideKit
@testable import SourcesKit
import Testing

struct OSMPlaceMapperTests {
    @Test func theKindRulesTakeTheFirstMatch() {
        #expect(OSMPlaceMapper.kind(for: ["amenity": "arts_centre"]) == .museum)
        #expect(OSMPlaceMapper.kind(for: ["tourism": "gallery"]) == .museum)
        #expect(OSMPlaceMapper.kind(for: ["tourism": "viewpoint"]) == .viewpoint)
        #expect(OSMPlaceMapper.kind(for: ["shop": "bakery"]) == .shop)
        #expect(OSMPlaceMapper.kind(for: ["shop": "greengrocer"]) == .grocery)
        #expect(OSMPlaceMapper.kind(for: ["man_made": "bridge"]) == .landmark)
        #expect(OSMPlaceMapper.kind(for: ["place": "square"]) == .landmark)
        #expect(OSMPlaceMapper.kind(for: ["amenity": "bench"]) == .other)
        #expect(OSMPlaceMapper.kind(for: ["amenity": "cafe", "tourism": "museum"]) == .cafe)
    }

    @Test func outdoorHistoricSitesAreOutdoors() {
        #expect(!OSMPlaceMapper.isIndoor(["historic": "archaeological_site"]))
        #expect(!OSMPlaceMapper.isIndoor(["historic": "city_gate"]))
        #expect(OSMPlaceMapper.isIndoor(["historic": "building"]))
        #expect(OSMPlaceMapper.isIndoor([:]))
    }

    @Test func aWebsiteCanComeFromTheContactTag() {
        #expect(OSMPlaceMapper.website(in: ["contact:website": " https://example.com/x "])
            == "https://example.com/x")
        #expect(OSMPlaceMapper.website(in: ["website": "   "]) == nil)
    }

}
