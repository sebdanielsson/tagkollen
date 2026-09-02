import Foundation
import Testing
@testable import TrafikverketKit

@Suite("HTML text sanitising")
struct HTMLTextTests {
    @Test func convertsBreaksAndStripsTags() {
        let raw = "Arlanda Express visas ej. <br>Spåruppgifterna är preliminära och kan ändras."
        #expect(raw.htmlToMarkdown == "Arlanda Express visas ej.\nSpåruppgifterna är preliminära och kan ändras.")
        #expect("SL-tåg omfattas ej. <BR> Spåruppgifterna".htmlToMarkdown == "SL-tåg omfattas ej.\nSpåruppgifterna")
    }

    @Test func convertsAnchorsToMarkdownLinks() {
        let raw = #"<div class="textLinks">Flygläget vid Arlanda: "#
            + #"<a runat="server" id="lank" title="Länk" href="http://www.swedavia.se/arlanda" target="_blank">Swedavia</a></div>"#
        #expect(raw.htmlToMarkdown == "Flygläget vid Arlanda: [Swedavia](http://www.swedavia.se/arlanda)")
        #expect(raw.strippingHTML == "Flygläget vid Arlanda: Swedavia")
    }

    @Test func decodesEntitiesAndLeavesPlainTextAlone() {
        #expect("Tom &amp; Jerry &#8211; &ouml;l".htmlToMarkdown == "Tom & Jerry – öl")
        #expect("Plain text".htmlToMarkdown == "Plain text")
        #expect(!"Plain text".containsHTML)
        #expect("a <br> b".containsHTML)
    }
}
