import XCTest
@testable import HubiplanKern

/// Gestaltung „Frisch mobil“, Etappe U4: Reiter „Neues“ und „Ich“ in vier Gruppen
/// (wie `NeuesIchTest` der Android-App).
final class NeuesIchTests: XCTestCase {
    func testNeuesFasstMitteilungenPinnwandUndUmfragenZusammen() {
        XCTAssertEqual(Neues.teile(pinnwand: false, umfragen: false), ["mitteilungen"])
        let alles = Neues.teile(pinnwand: true, umfragen: true)
        XCTAssertEqual(alles, ["mitteilungen", "pinnwand", "umfragen"])
        // Ohne Wahl oder ohne das Modul: Mitteilungen
        XCTAssertEqual(Neues.wahl(alles, nil), "mitteilungen")
        XCTAssertEqual(Neues.wahl(alles, "umfragen"), "umfragen")
        XCTAssertEqual(Neues.wahl(["mitteilungen"], "umfragen"), "mitteilungen")
        XCTAssertEqual(Neues.beschriftung("pinnwand", 2), "Pinnwand (2)")
        XCTAssertEqual(Neues.beschriftung("umfragen", 0), "Umfragen")
        XCTAssertEqual(Neues.beschriftung("mitteilungen", 120), "Mitteilungen (99+)")
    }

    func testIchInVierGruppen() {
        let gruppen = IchGruppe.gruppen(Set(IchGruppe.bereiche))
        XCTAssertEqual(gruppen.map(\.gruppe), [.geld, .mitmachen, .verein, .daten])
        XCTAssertEqual(gruppen[0].bereiche, ["rechnungen", "lastschrift", "nachweise", "bestellungen", "auslagen"])
        XCTAssertEqual(gruppen[2].bereiche, ["versammlungen", "dokumente"])
        XCTAssertEqual(gruppen[3].bereiche, ["daten", "kuendigung", "mitarbeiter"])
        // Pinnwand und Umfragen stehen unter „Neues“; alles andere hat genau eine Gruppe
        XCTAssertNil(IchGruppe.gruppe("pinnwand"))
        XCTAssertNil(IchGruppe.gruppe("umfragen"))
        XCTAssertEqual(gruppen.map(\.bereiche.count).reduce(0, +), IchGruppe.bereiche.count)
        XCTAssertTrue(IchGruppe.bereiche.allSatisfy { IchGruppe.gruppe($0) != nil })
        // Leere Gruppen fallen weg
        XCTAssertEqual(IchGruppe.gruppen(["pinnwand", "daten"]).map(\.gruppe), [.daten])
        XCTAssertEqual(IchGruppe.allCases.map(\.titel), ["Geld", "Mitmachen", "Verein", "Meine Daten"])
    }

    func testDarstellungWieGeraetHellOderDunkel() {
        // Ohne eigene Wahl folgt die App dem Gerät
        XCTAssertTrue(Darstellung.istDunkel("", geraetDunkel: true))
        XCTAssertFalse(Darstellung.istDunkel("", geraetDunkel: false))
        XCTAssertFalse(Darstellung.istDunkel("hell", geraetDunkel: true))
        XCTAssertTrue(Darstellung.istDunkel("dunkel", geraetDunkel: false))
        // Unbekanntes (z. B. aus einer neueren Fassung) folgt dem Gerät
        XCTAssertTrue(Darstellung.istDunkel("sepia", geraetDunkel: true))
        XCTAssertEqual(Darstellung.werte.map(Darstellung.name), ["Wie das Gerät", "Hell", "Dunkel"])
    }
}
