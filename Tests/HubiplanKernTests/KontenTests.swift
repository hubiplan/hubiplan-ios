import XCTest
@testable import HubiplanKern

final class KontenTests: XCTestCase {
    private func entry(_ id: String, _ server: String = "https://verein.example.de", _ email: String = "erika@example.org", _ display: String = "Erika Musterfrau") -> AccountEntry {
        AccountEntry(id: id, server: server, display: display, email: email)
    }

    func testHinzufuegenWaehlenEntfernen() {
        var list = AccountList()
        XCTAssertNil(list.active)
        XCTAssertNil(list.add(entry("a")))
        XCTAssertNil(list.add(entry("b", "https://kapelle.example.de")))
        XCTAssertEqual(list.active?.id, "b")
        XCTAssertTrue(list.select("a"))
        XCTAssertFalse(list.select("x"))
        XCTAssertEqual(list.active?.id, "a")
        list.remove("a")
        XCTAssertEqual(list.active?.id, "b")
        list.remove("b")
        XCTAssertNil(list.active)
        XCTAssertEqual(list.accounts, [])
    }

    func testDasselbeKontoNochEinmalErsetztDasAlte() {
        var list = AccountList()
        list.add(entry("a"))
        list.add(entry("b", "https://kapelle.example.de"))
        let replaced = list.add(entry("c", "https://verein.example.de", "ERIKA@example.org"))
        XCTAssertEqual(replaced?.id, "a")
        XCTAssertEqual(list.accounts.map(\.id), ["b", "c"])
        XCTAssertEqual(list.active?.id, "c")
        // Gleiche E-Mail auf anderer Instanz ist ein anderes Konto
        XCTAssertNil(list.add(entry("d", "https://anderer.example.de")))
        XCTAssertEqual(list.accounts.count, 3)
    }

    func testBezeichnungUndAuffrischen() {
        var list = AccountList()
        list.add(entry("a"))
        XCTAssertEqual(list.label(list.accounts[0]), "Erika Musterfrau")
        list.add(entry("b", "https://kapelle.example.de:8443"))
        XCTAssertEqual(list.label(list.accounts[0]), "Erika Musterfrau (verein.example.de)")
        XCTAssertEqual(list.label(list.accounts[1]), "Erika Musterfrau (kapelle.example.de:8443)")
        list.update("b", display: "", email: "e.musterfrau@example.org")
        XCTAssertEqual(list.label(list.accounts[1]), "e.musterfrau@example.org")
        XCTAssertEqual(list.label(list.accounts[0]), "Erika Musterfrau")
        list.update("x", display: "Niemand", email: "")
        XCTAssertEqual(list.accounts.count, 2)
    }

    func testSpeichernUndAltesEinzelkonto() throws {
        var list = AccountList()
        list.add(entry("a"))
        list.add(entry("b", "https://kapelle.example.de"))
        list.select("a")
        let copy = try JSONDecoder().decode(AccountList.self, from: try JSONEncoder().encode(list))
        XCTAssertEqual(copy, list)
        XCTAssertEqual(copy.active?.id, "a")
        // Gezeigtes Konto fehlt in den Daten: das erste nehmen
        let odd = try JSONDecoder().decode(AccountList.self, from: Data(#"{"accounts":[{"id":"a","server":"https://verein.example.de"}],"activeId":"weg"}"#.utf8))
        XCTAssertEqual(odd.active?.id, "a")
        // Konto aus der Zeit vor mehreren Konten: Kennung leer
        let old = try XCTUnwrap(AccountList.migrate(single: Data(#"{"server":"https://verein.example.de","display":"Erika Musterfrau","email":"erika@example.org"}"#.utf8)))
        XCTAssertEqual(old.active?.id, "")
        XCTAssertEqual(old.active?.host, "verein.example.de")
        XCTAssertNil(AccountList.migrate(single: Data("kaputt".utf8)))
    }

    func testFreieKennungUndGrenze() {
        var list = AccountList()
        list.add(entry("a"))
        var tries = ["", "a"]
        let id = list.freeId { tries.isEmpty ? "frei" : tries.removeFirst() }
        XCTAssertFalse(id.isEmpty)
        XCTAssertNotEqual(id, "a")
        XCTAssertFalse(list.full)
        for index in 0..<AccountList.limit { list.add(entry("k\(index)", "https://v\(index).example.de")) }
        XCTAssertTrue(list.full)
    }
}
