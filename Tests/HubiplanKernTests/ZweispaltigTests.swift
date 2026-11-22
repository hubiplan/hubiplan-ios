import XCTest
@testable import HubiplanKern

/// Gestaltung „Frisch mobil“, Etappe U7: Liste und Detail nebeneinander auf dem iPad
/// (wie `ListDetail` der Android-App).
final class ZweispaltigTests: XCTestCase {
    func testNurBreitNebeneinander() {
        XCTAssertTrue(Zweispaltig.gilt(breit: true))
        XCTAssertFalse(Zweispaltig.gilt(breit: false))
    }

    func testAuswahlUndPfad() {
        XCTAssertNil(Zweispaltig.auswahl([String]()))
        XCTAssertEqual(Zweispaltig.auswahl(["termin-1", "tiefer"]), "termin-1")
        // Eine neue Auswahl ersetzt das Detail, statt sich dahinter zu stapeln
        XCTAssertEqual(Zweispaltig.pfad("termin-2"), ["termin-2"])
        XCTAssertEqual(Zweispaltig.pfad(Int?.none), [])
    }
}
