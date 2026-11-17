import XCTest
@testable import HubiplanKern

/// Verbindungscode an die App gebunden (Gesamtaudit 15.11., APP-01). Dieselben Fälle wie in der
/// Android-App (BrowserLoginTest), erfundene Adressen.
final class BrowserLoginTests: XCTestCase {
    func testPruefwertWieRfc7636() {
        // Beispiel aus RFC 7636, Anhang B; derselbe Wert steht im Servertest
        XCTAssertEqual(
            BrowserLogin.challenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testGeheimnisZufaelligUndImErlaubtenZeichensatz() {
        let a = BrowserLogin.newVerifier()
        let b = BrowserLogin.newVerifier()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 43)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(a.unicodeScalars.allSatisfy { allowed.contains($0) })
        XCTAssertEqual(BrowserLogin.challenge(verifier: a).count, 43)
    }

    func testAnmeldeseiteMitPruefwert() {
        XCTAssertEqual(
            BrowserLogin.url(server: "verein.example.de", challenge: "abc")?.absoluteString,
            "https://verein.example.de/app/anmelden?challenge=abc"
        )
        XCTAssertEqual(BrowserLogin.url(server: "verein.example.de")?.absoluteString, "https://verein.example.de/app/anmelden")
        XCTAssertNil(BrowserLogin.url(server: "http://verein.example.de", challenge: "abc"))
        XCTAssertNil(BrowserLogin.url(server: "", challenge: "abc"))
    }

    func testStartlinkOhneCode() {
        XCTAssertEqual(
            BrowserLogin.parseStart("hubiplan://anmelden?server=https%3A%2F%2Fverein.example.de"),
            "https://verein.example.de"
        )
        XCTAssertEqual(
            BrowserLogin.parseStart("hubiplan://anmelden?server=https%3A%2F%2Fverein.example.de%3A8443"),
            "https://verein.example.de:8443"
        )
    }

    func testFremdeOderUnvollstaendigeStartlinksAblehnen() {
        XCTAssertNil(BrowserLogin.parseStart("hubiplan://anmelden?server=http%3A%2F%2Fverein.example.de"))
        XCTAssertNil(BrowserLogin.parseStart("hubiplan://anmelden?server=https%3A%2F%2Fverein.example.de%2Fpfad"))
        XCTAssertNil(BrowserLogin.parseStart("hubiplan://anmelden?server=https%3A%2F%2Fnutzer%40verein.example.de"))
        XCTAssertNil(BrowserLogin.parseStart("hubiplan://anmelden"))
        XCTAssertNil(BrowserLogin.parseStart("hubiplan://verbinden?server=https%3A%2F%2Fverein.example.de&code=x"))
        XCTAssertNil(BrowserLogin.parseStart("https://verein.example.de/app/anmelden"))
    }

    func testGeheimnisWirdMitgeschickt() async throws {
        let net = FakeTransport([FakeTransport.json(201, #"{"token":"hpd_erfunden","device":{"id":1,"name":"iPhone","platform":"ios","key":true},"user":{"email":"erika@example.org","display":"Erika Musterfrau"}}"#)])
        _ = try await Api(server: "https://verein.example.de", transport: net)
            .pair(code: "abc", deviceName: "iPhone", appVersion: "1", verifier: "geheim")
        let request = try XCTUnwrap(net.seen.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["verifier"] as? String, "geheim")
        XCTAssertEqual(body["code"] as? String, "abc")
    }
}
