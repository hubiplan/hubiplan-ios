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
            .sitzung("verein.example.de")
        )
        XCTAssertEqual(Sichtschutz.webDaten(server: "kaputt", uebrige: ["https://verein.example.de"]), .nichts)
        XCTAssertEqual(
            Sichtschutz.webDaten(server: "https://verein.example.de", uebrige: ["https://kapelle.example.org"]),
            .instanz("verein.example.de")
        )
    }

    /// Sicherheitsprüfung 26.11.2026, SEC-06: Links aus Serverantworten nur https, ohne
    /// Benutzerangabe, Kartenlinks nur zu den Kartendiensten.
    func testLinksNachAussen() {
        let osm = "https://www.openstreetmap.org/search?query=Musterstra%C3%9Fe+1"
        let google = "https://www.google.com/maps/dir/?api=1&destination=51.0%2C7.0"
        XCTAssertEqual(safeExternalUrl(osm, hosts: Kartenlinks.osm)?.absoluteString, osm)
        XCTAssertEqual(safeExternalUrl(google, hosts: Kartenlinks.google)?.absoluteString, google)
        XCTAssertNil(safeExternalUrl(google, hosts: Kartenlinks.osm))
        XCTAssertEqual(safeExternalUrl("https://cloud.example.org/call/abc")?.absoluteString, "https://cloud.example.org/call/abc")
        let boese: [String?] = [
            nil, "", "http://www.openstreetmap.org/", "tel:+4900000000", "javascript:alert(1)", "hubiplan://verbinden?code=x",
            "https://www.openstreetmap.org@boese.example/", "https://openstreetmap.org.boese.example/",
            "https://nutzer@www.openstreetmap.org/", "https://nutzer:geheim@www.openstreetmap.org/",
        ]
        for url in boese {
            XCTAssertNil(safeExternalUrl(url, hosts: Kartenlinks.osm), url ?? "nil")
        }
        XCTAssertNil(safeExternalUrl("https://nutzer:geheim@cloud.example.org/call/abc"))
        XCTAssertNil(safeExternalUrl("http://cloud.example.org/call/abc"))
    }
}
