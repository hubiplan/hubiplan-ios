import XCTest
@testable import HubiplanKern

/// „Über die App“, Rechtliches und Zugangswahl (UX-Audit 16.11., IOS-27, IOS-07).
final class RechtlichesTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func tearDown() { Texte.language = "de" }

    func testVerweiseDerInstanz() {
        XCTAssertEqual(Rechtliches.myAccount(server: server)?.absoluteString, "https://verein.example.de/mein-konto")
        XCTAssertEqual(Rechtliches.help(server: server)?.absoluteString, "https://verein.example.de/hilfe")
        XCTAssertEqual(Rechtliches.privacy(server: server, key: "sv-musterstadt")?.absoluteString, "https://verein.example.de/datenschutz/sv-musterstadt")
        XCTAssertEqual(Rechtliches.imprint(server: server, key: nil)?.absoluteString, "https://verein.example.de/impressum")
        // Schlüssel mit fremden Zeichen bleibt ein einzelner Pfadteil
        XCTAssertEqual(Rechtliches.imprint(server: server, key: "a/../b")?.absoluteString, "https://verein.example.de/impressum/a%2F..%2Fb")
        XCTAssertNil(Rechtliches.help(server: "http://verein.example.de"))
    }

    func testQuellcodeUndLizenz() {
        XCTAssertEqual(Rechtliches.sourceUrl(version: "1.2.0"), "https://github.com/hubiplan/hubiplan-ios/tree/v1.2.0")
        XCTAssertEqual(Rechtliches.sourceUrl(version: "$(MARKETING_VERSION)"), "https://github.com/hubiplan/hubiplan-ios")
        XCTAssertEqual(Rechtliches.licenseLine(version: "1.2.0"), "HUBIplan-App 1.2.0 · freie Software unter der GNU AGPL 3.0 oder neuer")
        XCTAssertTrue(Rechtliches.deleteInfo(server: server).contains("(verein.example.de)"))
    }

    func testZugangBeschriftung() throws {
        let json = #"""
        [{"id":1,"club_name":"Schützenverein Musterstadt","first_name":"Erika","last_name":"Musterfrau","imprint_key":"sv"},
         {"id":2,"club_name":"Schützenverein Musterstadt","club_display_name":"SV Musterstadt","first_name":"Lena","last_name":"Musterfrau"},
         {"id":3,"club_name":"Sportverein Beispiel","member_kind":"organization","member_name":"Beispiel GmbH"},
         {"id":4,"club_name":"Chor Probe"}]
        """#
        let list = try JSONDecoder().decode([PortalAccess].self, from: Data(json.utf8))
        XCTAssertEqual(list[0].label, "Schützenverein Musterstadt – Erika Musterfrau")
        XCTAssertEqual(list[1].label, "SV Musterstadt – Lena Musterfrau")
        XCTAssertNotEqual(list[0].label, list[1].label)
        XCTAssertEqual(list[2].label, "Sportverein Beispiel: Beispiel GmbH (Ansprechpartner)")
        XCTAssertEqual(list[3].label, "Chor Probe")
        XCTAssertEqual(list[0].imprintKey, "sv")
        XCTAssertNil(list[1].imprintKey)
        XCTAssertTrue(list[2].isContact)
        XCTAssertEqual(list[0].signedInAs, "Angemeldet als Mitglied von Schützenverein Musterstadt")
        XCTAssertEqual(list[2].signedInAs, "Angemeldet als Ansprechpartner von Beispiel GmbH in Sportverein Beispiel")
        Texte.language = "en"
        XCTAssertEqual(list[2].label, "Sportverein Beispiel: Beispiel GmbH (contact person)")
    }
}
