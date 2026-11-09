import Foundation
@testable import GuideKit
import Testing

struct GuideHTMLRendererTests {
    private static func edinburgh() throws -> Guide {
        try GuideKit.jsonDecoder().decode(Guide.self, from: Fixture.edinburghGuideData())
    }

    /// The text a reader sees: the style and the tags removed.
    private static func visibleText(_ html: String) -> String {
        html
            .replacing(/<style>[\s\S]*?<\/style>/, with: " ")
            .replacing(/<[^>]*>/, with: " ")
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
            .replacing("'", with: "&#39;")
    }

    @Test func everyDayTitleAppears() throws {
        let guide = try Self.edinburgh()
        let html = GuideHTMLRenderer().render(guide)
        #expect(guide.days.count == 3)
        for day in guide.days {
            #expect(html.contains(Self.escaped(day.copy.title)), "missing day title \(day.copy.title)")
        }
    }

    @Test func everyPlaceNameListTitleQuestionAndTasteNameAppears() throws {
        let guide = try Self.edinburgh()
        let html = GuideHTMLRenderer().render(guide)
        for place in guide.places.values {
            #expect(html.contains(Self.escaped(place.name)), "missing place \(place.name)")
        }
        for list in guide.lists {
            #expect(html.contains(Self.escaped(list.title)), "missing list \(list.title)")
        }
        for question in guide.openQuestions ?? [] {
            #expect(html.contains(Self.escaped(question)), "missing question \(question)")
        }
        for item in guide.tasting {
            #expect(html.contains(Self.escaped(item.name)), "missing tasting \(item.name)")
        }
    }

    @Test func everyPlaceHasACardAndStopsLinkToIt() throws {
        let guide = try Self.edinburgh()
        let html = GuideHTMLRenderer().render(guide)
        for placeId in guide.places.keys {
            #expect(html.contains("id=\"place-\(HTML.slug(placeId))\""), "no card for \(placeId)")
        }
        #expect(html.contains("href=\"#place-osm-node-2338447599\""))
    }

    @Test func namesAndAttributesAreEscaped() {
        let tom = Self.place(
            id: "manual:tom",
            name: "<b>\"Tom & Jerry's\"</b>",
            website: "https://example.com/shop?a=1&b=2"
        )
        let html = GuideHTMLRenderer().render(SampleGuide.make(places: [tom.id: tom]))
        #expect(html.contains("&lt;b&gt;&quot;Tom &amp; Jerry&#39;s&quot;&lt;/b&gt;"))
        #expect(!html.contains("<b>\"Tom"))
        #expect(html.contains("href=\"https://example.com/shop?a=1&amp;b=2\""))
        #expect(html.contains(">example.com</a>"))
    }

    @Test func onlyWebAddressesBecomeLinks() {
        let place = Self.place(id: "manual:risky", name: "Risky Place", website: "javascript:alert(1)")
        let html = GuideHTMLRenderer().render(SampleGuide.make(places: [place.id: place]))
        #expect(!html.contains("javascript"))
        #expect(html.contains("Risky Place"))
    }

    @Test func visibleTextHasNoIdsEnumNamesOrIsoDates() throws {
        let sample = try Self.edinburgh()
        for guide in [sample, SampleGuide.make()] {
            let visible = Self.visibleText(GuideHTMLRenderer().render(guide))
            #expect(!visible.contains("null"))
            #expect(!visible.contains(/\d{4}-\d{2}-\d{2}/), "an ISO date is visible")
            #expect(!visible.contains("osm:"))
            #expect(!visible.contains("manual:"))
            #expect(!visible.contains("fsq:"))
            for kind in PlaceKind.allCases where kind.rawValue != kind.rawValue.lowercased() {
                #expect(!visible.contains(kind.rawValue), "raw place kind \(kind.rawValue) is visible")
            }
        }
    }

    @Test func renderingTwiceGivesTheSameBytes() throws {
        let guide = try Self.edinburgh()
        #expect(GuideHTMLRenderer().render(guide) == GuideHTMLRenderer().render(guide))
    }

    @Test func leavesOutChecksAndNotesWhenThereAreNone() {
        let guide = SampleGuide.make(notes: nil, openQuestions: nil)
        let html = GuideHTMLRenderer().render(guide)
        #expect(!html.contains("Check before you go"))
        #expect(!html.contains("class=\"card trip-note\""))
    }

    @Test func printsAnA4PageWithOneDayPerPage() {
        let html = GuideHTMLRenderer().render(SampleGuide.make())
        #expect(html.contains("size: A4"))
        #expect(html.contains("break-before: page"))
        #expect(html.contains("<meta charset=\"utf-8\">"))
        #expect(!html.contains("<script"))
        #expect(!html.contains("http-equiv=\"refresh\""))
    }

    @Test func showsHoursOnEachTripDateAndUnconfirmedHoursPlainly() {
        let hours = OpeningHours(
            hoursKnown: true,
            weekly: [WeeklyPeriod(weekday: .sunday, open: SampleGuide.time("10:00"), close: SampleGuide.time("16:00"))],
            exceptions: []
        )
        let cafe = Self.place(id: "manual:hours", name: "Hours Cafe", hours: hours)
        let unknown = Self.place(
            id: "manual:unknown",
            name: "Unknown Cafe",
            hours: OpeningHours(hoursKnown: false, weekly: [], exceptions: [])
        )
        let trip = SampleGuide.trip(start: "2025-11-23", end: "2025-11-24")
        let guide = SampleGuide.make(trip: trip, places: [cafe.id: cafe, unknown.id: unknown])
        let visible = Self.visibleText(GuideHTMLRenderer().render(guide))
        #expect(visible.contains("Sun 23 Nov: 10:00–16:00"))
        #expect(visible.contains("Mon 24 Nov: Closed"))
        #expect(visible.contains("Hours not confirmed, check before you go"))
    }

    private static func place(
        id: String,
        name: String,
        hours: OpeningHours = OpeningHours(hoursKnown: false, weekly: [], exceptions: []),
        website: String? = nil
    ) -> Place {
        Place(
            id: id,
            name: name,
            kind: .cafe,
            location: PlaceLocation(
                coordinate: SampleGuide.coordinate(55.95, -3.19),
                address: "1 Example Street",
                approximate: false
            ),
            hours: hours,
            priceLevel: nil,
            booking: PlaceBooking(needed: false, url: nil),
            indoor: true,
            images: [],
            facts: [],
            copy: PlaceCopy(tag: "Test", blurb: "A made-up place."),
            website: website
        )
    }
}
