import XCTest
@testable import HubiplanKern

/// IOS-25: Reiter und Zugang überstehen das Beenden der App.
final class ZustandTests: XCTestCase {
    func testReiterNurWennVorhanden() {
        XCTAssertEqual(Zustand.reiter("aufgaben", available: Zustand.festeReiter + ["aufgaben"], fallback: "termine"), "aufgaben")
        XCTAssertEqual(Zustand.reiter("aufgaben", available: Zustand.festeReiter, fallback: "termine"), "termine")
        XCTAssertEqual(Zustand.reiter(nil, available: Zustand.festeReiter, fallback: "termine"), "termine")
    }

    /// Gestaltung „Frisch mobil“, Etappe U2: Reiter wie in der Android-App (`ReiterTest`).
    func testVierFesteReiterUndEinFuenfterJeRolle() {
        XCTAssertEqual(Zustand.festeReiter, ["start", "termine", "mitteilungen", "ausweis"])
        XCTAssertEqual(Zustand.fuenfteReiter(verwaltung: true, noten: true, aufgaben: true), ["verwaltung", "noten", "aufgaben"])
        XCTAssertEqual(Zustand.fuenfterReiter(["verwaltung", "noten", "aufgaben"], wahl: ""), "verwaltung")
        XCTAssertEqual(Zustand.fuenfterReiter(["noten", "aufgaben"], wahl: nil), "noten")
        XCTAssertEqual(Zustand.fuenfterReiter(["aufgaben"], wahl: ""), "aufgaben")
        XCTAssertNil(Zustand.fuenfterReiter([], wahl: "noten"))
        // Eigene Wahl gilt, solange es den Bereich gibt
        XCTAssertEqual(Zustand.fuenfterReiter(["verwaltung", "aufgaben"], wahl: "aufgaben"), "aufgaben")
        XCTAssertEqual(Zustand.fuenfterReiter(["verwaltung", "aufgaben"], wahl: "noten"), "verwaltung")
        for verwaltung in [false, true] {
            for noten in [false, true] {
                for aufgaben in [false, true] {
                    let moeglich = Zustand.fuenfteReiter(verwaltung: verwaltung, noten: noten, aufgaben: aufgaben)
                    let leiste = Zustand.leiste(moeglich, wahl: "")
                    XCTAssertLessThanOrEqual(leiste.count, 5)
                    XCTAssertEqual(Array(leiste.prefix(4)), Zustand.festeReiter)
                    // Nichts geht verloren: Leiste und „Start“ zusammen zeigen alle Bereiche
                    XCTAssertEqual(Set(leiste.dropFirst(4) + Zustand.weitereReiter(moeglich, wahl: "")), Set(moeglich))
                }
            }
        }
        XCTAssertEqual(Zustand.weitereReiter(["verwaltung", "noten", "aufgaben"], wahl: "noten"), ["verwaltung", "aufgaben"])
    }

    func testZugangNurWennNochDa() {
        XCTAssertEqual(Zustand.zugang(saved: 7, available: [3, 7]), 7)
        XCTAssertEqual(Zustand.zugang(saved: 9, available: [3, 7]), 3)
        XCTAssertEqual(Zustand.zugang(saved: nil, available: [3, 7]), 3)
        XCTAssertNil(Zustand.zugang(saved: 7, available: []))
    }

    func testZugangJeKonto() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ZustandTests-\(UUID().uuidString)"))
        Zustand.merke(zugang: 7, account: "a", defaults: defaults)
        Zustand.merke(zugang: 3, account: "b", defaults: defaults)
        XCTAssertEqual(Zustand.gespeicherterZugang(account: "a", defaults: defaults), 7)
        XCTAssertEqual(Zustand.gespeicherterZugang(account: "b", defaults: defaults), 3)
        Zustand.merke(zugang: nil, account: "a", defaults: defaults)
        XCTAssertNil(Zustand.gespeicherterZugang(account: "a", defaults: defaults))
    }

    /// IOS-09: Aufnahme zählt nur, was die Person eingibt.
    func testAufnahmeEingabe() {
        var draft = AdmitDraft(entry: "2026-11-18")
        draft.type = 2
        XCTAssertFalse(draft.hasInput)
        draft.lastName = "Muster"
        XCTAssertTrue(draft.hasInput)
    }
}
