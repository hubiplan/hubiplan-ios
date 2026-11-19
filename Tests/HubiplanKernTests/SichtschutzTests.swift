import XCTest
@testable import HubiplanKern

/// Gesamtaudit 19.11.2026, S-09 (wie Android `Gesamtaudit1119Test`).
final class SichtschutzTests: XCTestCase {
    func testStandardmaessigVerdeckt() {
        XCTAssertTrue(Sichtschutz.verdecken(aktiv: false, erlaubt: false))
    }

    func testVornNieVerdeckt() {
        XCTAssertFalse(Sichtschutz.verdecken(aktiv: true, erlaubt: false))
        XCTAssertFalse(Sichtschutz.verdecken(aktiv: true, erlaubt: true))
    }

    func testAbschaltbar() {
        XCTAssertFalse(Sichtschutz.verdecken(aktiv: false, erlaubt: true))
    }

    func testEinstellungVorgabeNein() {
        let name = "sichtschutz-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(Sichtschutz.erlaubt(defaults: defaults))
        Sichtschutz.setze(erlaubt: true, defaults: defaults)
        XCTAssertTrue(Sichtschutz.erlaubt(defaults: defaults))
    }

    func testWebDatenNachDemAbmelden() {
        XCTAssertEqual(Sichtschutz.webDaten(server: "https://verein.example.de", uebrige: []), .alles)
        XCTAssertEqual(
            Sichtschutz.webDaten(server: "https://verein.example.de", uebrige: ["https://Verein.example.de"]),
            .nichts
        )
        XCTAssertEqual(
            Sichtschutz.webDaten(server: "https://verein.example.de", uebrige: ["https://kapelle.example.org"]),
            .instanz("verein.example.de")
        )
    }
}
