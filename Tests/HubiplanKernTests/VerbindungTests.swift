import XCTest
@testable import HubiplanKern

/// Dieselben Fälle wie in der Android-App (PairingLinkTest), erfundene Adressen.
final class VerbindungTests: XCTestCase {
    func testQrCodeAusMeinKonto() {
        XCTAssertEqual(
            PairingLink.parse("https://verein.example.de/app/verbinden#code=abc-123_X"),
            PairingLink(server: "https://verein.example.de", code: "abc-123_X")
        )
    }

    func testMitPort() {
        XCTAssertEqual(PairingLink.parse("https://test.example:8443/app/verbinden#code=x")?.server, "https://test.example:8443")
    }

    func testFremdeCodesAblehnen() {
        XCTAssertNil(PairingLink.parse("http://verein.example.de/app/verbinden#code=abc"))
        XCTAssertNil(PairingLink.parse("https://verein.example.de/anderes#code=abc"))
        XCTAssertNil(PairingLink.parse("https://verein.example.de/app/verbinden"))
        XCTAssertNil(PairingLink.parse("https://verein.example.de/app/verbinden#code="))
        XCTAssertNil(PairingLink.parse("WIFI:S:netz;T:WPA;P:geheim;;"))
        XCTAssertNil(PairingLink.parse(""))
    }

    func testLinkAufDemselbenTelefon() {
        XCTAssertEqual(
            PairingLink.parse("hubiplan://verbinden?server=https%3A%2F%2Fverein.example.de&code=abc"),
            PairingLink(server: "https://verein.example.de", code: "abc")
        )
        XCTAssertEqual(
            PairingLink.parse("hubiplan://verbinden?link=https%3A%2F%2Fverein.example.de%2Fapp%2Fverbinden%23code%3Dabc"),
            PairingLink(server: "https://verein.example.de", code: "abc")
        )
        XCTAssertNil(PairingLink.parse("hubiplan://verbinden?server=http%3A%2F%2Fverein.example.de&code=abc"))
        XCTAssertNil(PairingLink.parse("hubiplan://verbinden?server=https%3A%2F%2Fverein.example.de%2Fpfad&code=abc"))
        XCTAssertNil(PairingLink.parse("hubiplan://verbinden?server=https%3A%2F%2Fverein.example.de"))
        XCTAssertNil(PairingLink.parse("hubiplan://anderes?server=https%3A%2F%2Fverein.example.de&code=abc"))
        XCTAssertNil(PairingLink.parse("hubiplan://verbinden?link=hubiplan%3A%2F%2Fverbinden"))
    }

    func testServeradresse() {
        XCTAssertEqual(normalizeServer(" verein.example.de/ "), "https://verein.example.de")
        XCTAssertEqual(normalizeServer("https://verein.example.de/mein-konto"), "https://verein.example.de")
        XCTAssertEqual(normalizeServer("Verein.Example.de"), "https://verein.example.de")
        XCTAssertNil(normalizeServer("http://verein.example.de"))
        XCTAssertNil(normalizeServer(""))
        XCTAssertEqual(passwordResetUrl("verein.example.de"), "https://verein.example.de/passwort-vergessen")
    }

    /// Pfade aus Serverantworten bleiben auf der Instanz.
    func testServerLinkBleibtAufDerInstanz() {
        let server = "https://verein.example.de"
        XCTAssertEqual(serverLink(server: server, path: "/api/app/v1/me/"), "https://verein.example.de/api/app/v1/me/")
        XCTAssertNil(serverLink(server: server, path: ".boese.example/x"))
        XCTAssertNil(serverLink(server: server, path: "//boese.example/x"))
        XCTAssertNil(serverLink(server: server, path: "/\\boese.example"))
        XCTAssertNil(serverLink(server: server, path: "/a b"))
        XCTAssertNil(serverLink(server: server, path: "/a\nb"))
        XCTAssertNil(serverLink(server: "http://verein.example.de", path: "/x"))
        XCTAssertEqual(serverLink(server: "https://test.example:8443/", path: "/x?q=1"), "https://test.example:8443/x?q=1")
    }
}
