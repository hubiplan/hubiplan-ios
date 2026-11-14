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

    // Passkey auf dem iPhone: Anmelden im eingebetteten Browser (docs/app.md in hubiplan)
    func testPasskeyAnmeldeseite() {
        XCTAssertEqual(BrowserLogin.url(server: "verein.example.de")?.absoluteString, "https://verein.example.de/app/anmelden")
        XCTAssertEqual(BrowserLogin.url(server: "https://Test.Example:8443/")?.absoluteString, "https://test.example:8443/app/anmelden")
        XCTAssertNil(BrowserLogin.url(server: "http://verein.example.de"))
        XCTAssertNil(BrowserLogin.url(server: " "))
    }

    func testPasskeyRueckrufNurVonDerselbenInstanz() {
        let ok = URL(string: "hubiplan://verbinden?server=https%3A%2F%2Fverein.example.de&code=Ab-_9")!
        XCTAssertEqual(BrowserLogin.pairing(callback: ok, server: "verein.example.de"), PairingLink(server: "https://verein.example.de", code: "Ab-_9"))
        // Ein Code einer anderen Adresse wird nicht übernommen
        XCTAssertNil(BrowserLogin.pairing(callback: ok, server: "anderer.example.de"))
        XCTAssertNil(BrowserLogin.pairing(callback: URL(string: "hubiplan://termin?id=1")!, server: "verein.example.de"))
    }

    func testInstanzNenntPasskeyWege() throws {
        let mit = try JSONDecoder().decode(Instance.self, from: Data(#"{"product":"HUBIplan","api_version":1,"passkey":["android","browser"]}"#.utf8))
        XCTAssertEqual(mit.passkey, ["android", "browser"])
        let ohne = try JSONDecoder().decode(Instance.self, from: Data(#"{"product":"HUBIplan","api_version":1}"#.utf8))
        XCTAssertEqual(ohne.passkey, [])
    }
}
