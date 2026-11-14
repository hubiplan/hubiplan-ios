import XCTest
@testable import HubiplanKern

/// Dieselben Fälle wie in der Android-App (CircularContentTest).
final class MitteilungenTests: XCTestCase {
    func testZielEnthaeltGenauZugangUndSchreibenOhneSitzungsdaten() {
        XCTAssertEqual(
            CircularText.webUrl(server: "https://club.example.org:8443/alt?token=geheim#fragment", access: 9, circular: 17),
            "https://club.example.org:8443/mein-bereich/rundschreiben?zugang=9&schreiben=17"
        )
        XCTAssertNil(CircularText.webUrl(server: "http://club.example.org", access: 9, circular: 17))
        XCTAssertNil(CircularText.webUrl(server: "https://club.example.org", access: 0, circular: 17))
        XCTAssertNil(CircularText.webUrl(server: "https://club.example.org", access: 9, circular: -1))
    }

    func testAbsaetzeUndListen() {
        let blocks = CircularText.blocks("Hallo\r\nWelt\r\n\r\n- eins\r\n• zwei\r\n\r\n1. zuerst\r\n2) danach")
        XCTAssertEqual(blocks.map(\.kind), ["p", "ul", "ol"])
        XCTAssertEqual(blocks[0].lines, ["Hallo", "Welt"])
        XCTAssertEqual(blocks[1].lines, ["eins", "zwei"])
        XCTAssertEqual(blocks[2].lines, ["zuerst", "danach"])
        XCTAssertEqual(CircularText.blocks(""), [])
        // Leerzeile trennt auch gleichartige Blöcke
        XCTAssertEqual(CircularText.blocks("a\n\nb").map(\.lines), [["a"], ["b"]])
    }

    func testFormatierungUndNurErlaubteLinkschemata() {
        let spans = CircularText.inline("**wichtig** *leise* [Plan](https://club.example.org/plan) [Kontakt](mailto:board@example.org) [Falsch](javascript:alert)")
        XCTAssertEqual(spans.map(\.text).joined(), "wichtig leise Plan Kontakt [Falsch](javascript:alert)")
        XCTAssertEqual(spans.first, CircularSpan(text: "wichtig", bold: true))
        XCTAssertTrue(spans.contains(CircularSpan(text: "leise", italic: true)))
        XCTAssertEqual(spans.compactMap(\.link), ["https://club.example.org/plan", "mailto:board@example.org"])
        XCTAssertEqual(CircularText.inline("***beides***").first?.bold, true)
        XCTAssertEqual(CircularText.inline("<b>kein HTML</b>"), [CircularSpan(text: "<b>kein HTML</b>")])
        XCTAssertEqual(CircularText.inline(""), [])
    }

    func testMitteilungenLesen() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"[{"id":17,"subject":"Antreten","sender":"Zug 1","kind_label":"Kurzmitteilung","sent_at":"2026-11-13T18:00:00+01:00","body":"Heute 18 Uhr am Zelt","attachments":[{"id":4,"name":"Plan.pdf","size":12345,"content_type":"application/pdf"}],"channel":"app"},{"id":16,"subject":"Einladung"}]"#)])
        let items = try await Api(server: "https://verein.example.de", transport: net, tokens: FakeTokens("hpd_a")).circulars(accessId: 3)
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/portal/3/circulars/")
        XCTAssertEqual(items.map(\.id), [17, 16])
        XCTAssertEqual(items[0].attachments.first?.name, "Plan.pdf")
        XCTAssertNotNil(items[0].sent)
        XCTAssertNil(items[1].body)
        XCTAssertNil(items[1].sent)
        XCTAssertEqual(items[1].attachments, [])
    }
}
