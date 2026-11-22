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
