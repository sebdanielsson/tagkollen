import Foundation
import Testing
@testable import TrafikverketKit

@Suite("Request rendering")
struct RequestRenderingTests {
    @Test func rendersQueryAttributesAndFilters() {
        let query = Query<TrainPosition>()
            .filter(.greaterThan("TimeStamp", "$dateadd(-0.00:02:00)"), .equal("Status.Active", true))
            .include("Train.AdvertisedTrainNumber", "Position.WGS84")
            .limit(500)
            .orderBy(Sort("TimeStamp", .descending))
            .changeID("0")
            .sseURL()

        let xml = query.renderXML()
        #expect(xml.contains("objecttype=\"TrainPosition\""))
        #expect(xml.contains("namespace=\"järnväg.trafikinfo\""))
        #expect(xml.contains("schemaversion=\"1.1\""))
        #expect(xml.contains("limit=\"500\""))
        #expect(xml.contains("orderby=\"TimeStamp desc\""))
        #expect(xml.contains("changeid=\"0\""))
        #expect(xml.contains("sseurl=\"true\""))
        #expect(xml.contains("<GT name=\"TimeStamp\" value=\"$dateadd(-0.00:02:00)\" />"))
        #expect(xml.contains("<EQ name=\"Status.Active\" value=\"true\" />"))
        #expect(xml.contains("<INCLUDE>Train.AdvertisedTrainNumber</INCLUDE>"))
    }

    @Test func escapesXMLSpecialCharacters() {
        let query = Query<TrainStation>().filter(.like("AdvertisedLocationName", "Tom & \"Jerry\" <x>"))
        let xml = query.renderXML()
        #expect(xml.contains("value=\"Tom &amp; &quot;Jerry&quot; &lt;x&gt;\""))
        let doc = RequestDocument.render(apiKey: "a<b", queries: [xml])
        #expect(doc.contains("authenticationkey=\"a&lt;b\""))
        #expect(doc.hasPrefix("<REQUEST>"))
        #expect(doc.hasSuffix("</REQUEST>\n"))
    }

    @Test func rendersNestedGroups() {
        let f: Filter = .or([.equal("A", "1"), .and([.equal("B", "2"), .not([.exists("C", false)])])])
        var out = ""
        f.render(into: &out, indent: 0)
        #expect(out.contains("<OR>"))
        #expect(out.contains("<AND>"))
        #expect(out.contains("<NOT>"))
        #expect(out.contains("<EXISTS name=\"C\" value=\"false\" />"))
    }

    @Test func swedishTimeFormatting() {
        // 2026-07-01 12:00 UTC is 14:00 CEST.
        let date = Date(timeIntervalSince1970: 1_782_907_200)
        #expect(SwedishTime.dateTimeString(date) == "2026-07-01T14:00:00")
        #expect(SwedishTime.dateString(date) == "2026-07-01")
    }
}
