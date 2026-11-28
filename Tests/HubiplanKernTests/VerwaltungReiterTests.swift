import XCTest
@testable import HubiplanKern

/// Konten ohne Mitgliederbereich: Reiter der Verwaltung statt Start, Termine, Neues
/// (wie `VerwaltungReiterTest` der Android-App).
final class VerwaltungReiterTests: XCTestCase {
    func testNurOhneMitgliederbereichUndMitVerwaltung() {
        XCTAssertTrue(VerwaltungReiter.nurVerwaltung(geladen: true, zugaenge: 0, verwaltet: true))
        // Mit Mitgliederbereich bleibt es bei Start, Termine, Neues, Ich und dem fünften Reiter
        XCTAssertFalse(VerwaltungReiter.nurVerwaltung(geladen: true, zugaenge: 1, verwaltet: true))
        XCTAssertFalse(VerwaltungReiter.nurVerwaltung(geladen: true, zugaenge: 0, verwaltet: false))
        XCTAssertFalse(VerwaltungReiter.nurVerwaltung(geladen: false, zugaenge: 0, verwaltet: true))
    }

    func testKassenbuchJeBereichEinReiter() {
        let nurKasse = VerwaltungReiter.reiter([.tasks, .finance], [])
        XCTAssertEqual(nurKasse.map(\.key), ["start", "s:finance"])
        XCTAssertEqual(nurKasse[0].bereiche, [.tasks])
        XCTAssertTrue(nurKasse[1].einzeln)
        let mitRechnungen = VerwaltungReiter.reiter([.tasks, .finance, .billing, .partners], [])
        XCTAssertEqual(mitRechnungen.map(\.key), ["start", "s:finance", "s:billing", "s:partners"])
        XCTAssertEqual(mitRechnungen.map(\.titel), ["Start", "Kassenbuch", "Rechnungen", "Partner"])
        XCTAssertTrue(mitRechnungen.dropFirst().allSatisfy(\.einzeln))
    }

    func testMehrBereicheWerdenGruppen() {
        let drei = VerwaltungReiter.reiter([.tasks, .events, .todos, .members, .finance, .billing], [])
        XCTAssertEqual(drei.map(\.key), ["start", "g:planen", "s:members", "g:verwaltung"])
        // Gruppe mit genau einem Bereich öffnet ihn direkt
        XCTAssertTrue(drei[2].einzeln)
        XCTAssertEqual(drei[3].bereiche, [.finance, .billing])
    }

    func testVierGruppenLetzteUnterMehr() {
        let alle = VerwaltungReiter.reiter(AdminSection.allCases, [])
        XCTAssertEqual(alle.map(\.key), ["start", "g:planen", "g:verein", "mehr"])
        XCTAssertEqual(alle.count, VerwaltungReiter.mittlere + 1)
        XCTAssertEqual(Set(alle.last?.bereiche ?? []), [.meetings, .bookings, .competitions, .finance, .billing, .partners])
        // Jeder Bereich außer „Zu erledigen“ steht in genau einem Reiter
        XCTAssertEqual(alle.dropFirst().map(\.bereiche.count).reduce(0, +), AdminSection.allCases.count - 1)
    }

    func testHauptmenuepunkteDerEinheit() {
        let menue = [
            MenuGroup(id: "geld", label: "Geld", items: ["finanzen"]),
            MenuGroup(id: "leute", label: "Leute", items: ["mitglieder", "termine"]),
        ]
        let reiter = VerwaltungReiter.reiter([.tasks, .events, .members, .applications, .finance, .billing], menue)
        XCTAssertEqual(reiter.map(\.key), ["start", "g:m:geld", "g:m:leute"])
        XCTAssertEqual(reiter.map(\.titel), ["Start", "Geld", "Leute"])
    }

    func testGewaehlterReiterFaelltAufStartZurueck() {
        let reiter = VerwaltungReiter.reiter([.tasks, .finance], [])
        XCTAssertEqual(VerwaltungReiter.gewaehlt(reiter, "s:finance")?.key, "s:finance")
        // Einheit gewechselt, den Reiter gibt es dort nicht
        XCTAssertEqual(VerwaltungReiter.gewaehlt(reiter, "s:billing")?.key, "start")
    }

    func testHinweisDerVerwaltungAusDemPush() {
        let m = PushMessage.parse(#"{"v":1,"t":"admin","unit":7,"kind":"incoming_review","title":"Neue Eingangsrechnung","text":"Verein"}"#)
        XCTAssertEqual(m?.type, "admin")
        XCTAssertEqual(m?.unit, 7)
        XCTAssertEqual(m?.kind, "incoming_review")
    }
}
