import XCTest
@testable import HubiplanKern

/// Gestaltung „Frisch mobil“, Etappe U5: Startliste der Verwaltung als Arbeitsplatz
/// (wie `VerwaltungStartTest` der Android-App).
final class VerwaltungStartTests: XCTestCase {
    private let verein = AdminUnit(
        id: 1,
        name: "Verein",
        permissions: ["todos.view", "members.view", "events.view", "finance.view", "finance.edit", "billing.view"],
        stufen: true
    )

    func testBereicheInVierGruppen() {
        let gruppen = VerwaltungGruppe.gruppen(AdminSection.allCases)
        XCTAssertEqual(gruppen.map(\.gruppe), [.planen, .verein, .vereinsleben, .verwaltung])
        // „Zu erledigen“ steht für sich; alles andere hat genau eine Gruppe
        XCTAssertNil(AdminSection.tasks.gruppe)
        XCTAssertEqual(gruppen.map(\.bereiche.count).reduce(0, +), AdminSection.allCases.count - 1)
        // Leere Gruppen fallen weg, die Reihenfolge der Bereiche bleibt
        let wenige = VerwaltungGruppe.gruppen([.tasks, .events, .todos, .members])
        XCTAssertEqual(wenige.map(\.gruppe), [.planen, .verein])
        XCTAssertEqual(wenige[0].bereiche, [.events, .todos])
        XCTAssertEqual(wenige[1].bereiche, [.members])
        XCTAssertEqual(VerwaltungGruppe.gruppen(verein.sections).last?.bereiche, [.finance, .billing])
        // Jeder Bereich hat ein eigenes Symbol
        XCTAssertEqual(Set(AdminSection.allCases.map(\.symbol)).count, AdminSection.allCases.count)
    }

    func testGruppenNachHauptmenuepunktenDerEinheit() throws {
        // Ohne Angabe vom Server: die festen Gruppen
        XCTAssertEqual(
            VerwaltungGruppe.gruppen(AdminSection.allCases, []).map(\.titel),
            ["Planen", "Verein", "Vereinsleben", "Verwaltung"]
        )
        // Mit Angabe: Hauptmenüpunkte in Leistenreihenfolge, leere entfallen
        let json = """
        {"id": 1, "name": "Verein", "menu_groups": [
          {"id": "start", "label": "Start", "items": ["start"]},
          {"id": "mitglieder", "label": "Mitglieder", "items": ["mitglieder"]},
          {"id": "b1", "label": "Schießsport", "items": ["wettbewerbe", "termine"]},
          {"id": "finanzen", "label": "Finanzen", "items": ["finanzen"]},
          {"id": "verein", "label": "Verein", "items": ["geschaeftspartner"]}]}
        """
        let unit = try JSONDecoder().decode(AdminUnit.self, from: Data(json.utf8))
        XCTAssertEqual(unit.menuGroups.count, 5)
        let bereiche: [AdminSection] = [.tasks, .events, .members, .competitions, .finance, .partners, .obligations]
        let ergebnis = VerwaltungGruppe.gruppen(bereiche, unit.menuGroups)
        XCTAssertEqual(ergebnis.map(\.titel), ["Mitglieder", "Schießsport", "Finanzen", "Verein", "Weitere"])
        XCTAssertEqual(ergebnis[1].bereiche, [.events, .competitions])
        // Fristen hat keinen Platz in den Gruppen: unter „Weitere“, „Zu erledigen“ nie in einer Gruppe
        XCTAssertEqual(ergebnis.last?.bereiche, [.obligations])
        // Jeder Bereich außer „Zu erledigen“ gehört zu einem Menüpunkt der Web-Oberfläche
        XCTAssertEqual(AdminSection.allCases.filter { $0.modul == nil }, [.tasks])
        // Ältere Server ohne Feld
        let alt = try JSONDecoder().decode(AdminUnit.self, from: Data(#"{"id": 2, "name": "B"}"#.utf8))
        XCTAssertEqual(alt.menuGroups, [])
    }

    func testSucheNachNameUndBeschreibung() {
        let alle = AdminSection.allCases
        XCTAssertEqual(VerwaltungGruppe.suche(alle, "  "), alle)
        XCTAssertEqual(VerwaltungGruppe.suche(alle, "kassenbuch"), [.finance])
        // Beschreibung zählt mit, Groß- und Kleinschreibung nicht
        XCTAssertEqual(VerwaltungGruppe.suche(alle, "KONTOSTÄNDE"), [.finance])
        // Alle Wörter müssen vorkommen
        XCTAssertEqual(VerwaltungGruppe.suche(alle, "geburtstage jubiläen"), [.occasions])
        XCTAssertEqual(VerwaltungGruppe.suche(alle, "gibt es nicht"), [])
    }

    func testNeuJeNachRechten() {
        XCTAssertEqual(verein.neuAktionen, [.quittung, .buchung, .termin, .aufgabe])
        // Ohne „Kasse bearbeiten“ keine Quittung und keine Buchung
        let ohneKasse = AdminUnit(id: 1, name: "Verein", permissions: ["todos.view", "events.view", "finance.view"], stufen: true)
        XCTAssertEqual(ohneKasse.neuAktionen, [.termin, .aufgabe])
        // Untereinheit: nie Kasse
        let zug = AdminUnit(id: 4, name: "Zug", permissions: ["todos.view", "events.view", "finance.edit"], scope: "d", stufen: true)
        XCTAssertEqual(zug.neuAktionen, [.termin, .aufgabe])
        XCTAssertEqual(AdminUnit(id: 2, name: "Verein", permissions: ["members.view"], stufen: true).neuAktionen, [])
    }
}
