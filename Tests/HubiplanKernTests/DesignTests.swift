import XCTest
@testable import HubiplanKern

/// Design „Frisch“: Abzeichen und Datumskästchen wie in der Weboberfläche und der Android-App.
final class DesignTests: XCTestCase {
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    func testAbzeichenSindHellUndDunkelLesbar() throws {
        for zustand in Design.Zustand.allCases {
            for dunkel in [false, true] {
                let farben = Design.farben(zustand, dunkel: dunkel)
                let kontrast = try XCTUnwrap(Design.kontrast(farben.schrift, farben.flaeche))
                XCTAssertGreaterThanOrEqual(kontrast, 4.5, "\(zustand), dunkel=\(dunkel)")
            }
        }
    }

    func testZustandsfarbenWieInDerWeboberflaeche() {
        XCTAssertEqual(Design.farben(.gut, dunkel: false).schrift, "#1d6b46")
        XCTAssertEqual(Design.farben(.fehler, dunkel: false).flaeche, "#fbe9e7")
        XCTAssertEqual(Design.farben(.warnung, dunkel: true).schrift, "#f4cf86")
        XCTAssertEqual(Design.radius, 6)
        XCTAssertEqual(Design.radiusGross, 8)
    }

    func testZustandDerRueckmeldung() {
        XCTAssertEqual(Design.zustand(abgesagt: false, antwort: "yes"), .gut)
        XCTAssertEqual(Design.zustand(abgesagt: false, antwort: "no"), .neutral)
        XCTAssertEqual(Design.zustand(abgesagt: false, antwort: "maybe"), .hinweis)
        XCTAssertEqual(Design.zustand(abgesagt: false, antwort: nil), .warnung)
        XCTAssertEqual(Design.zustand(abgesagt: true, antwort: "yes"), .fehler)
    }

    func testKontrast() throws {
        XCTAssertEqual(try XCTUnwrap(Design.kontrast("#000000", "#ffffff")), 21, accuracy: 0.01)
        XCTAssertNil(Design.kontrast("rot", "#ffffff"))
    }

    func testDatumskaestchenJeSprache() {
        let nov = Design.datumKaestchen("2026-11-14T19:00:00+01:00", timeZone: berlin, englisch: false)
        XCTAssertEqual(nov?.tag, "14")
        XCTAssertEqual(nov?.monat, "NOV")
        XCTAssertEqual(Design.datumKaestchen("2027-03-03T10:00:00+01:00", timeZone: berlin, englisch: false)?.monat, "MÄR")
        XCTAssertEqual(Design.datumKaestchen("2027-03-03T10:00:00+01:00", timeZone: berlin, englisch: true)?.monat, "MAR")
        // Zeitzone des Geräts zählt: 23:30 UTC ist in Berlin schon der nächste Tag
        let dez = Design.datumKaestchen("2026-11-30T23:30:00Z", timeZone: berlin, englisch: false)
        XCTAssertEqual(dez?.tag, "1")
        XCTAssertEqual(dez?.monat, "DEZ")
        XCTAssertNil(Design.datumKaestchen("kein Datum", timeZone: berlin, englisch: false))
    }
}
