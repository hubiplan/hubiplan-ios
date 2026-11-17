import XCTest
@testable import HubiplanKern

/// Anmeldung mit E-Mail und Passwort in der App (UX-Audit 16.11., IOS-06), wie in der Android-App.
final class AnmeldungTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let paired = FakeTransport.json(201, #"{"token":"hpd_p","device":{"id":9,"name":"iPhone","platform":"ios","current":true},"user":{"email":"erika@example.org","display":"Erika Musterfrau"}}"#)
    private let angemeldet = FakeTransport.json(200, #"{"status":200,"data":{"user":{"id":1}},"meta":{"session_token":"sess1","is_authenticated":true}}"#)
    private let codeNoetig = FakeTransport.json(401, #"{"status":401,"data":{"flows":[{"id":"login"},{"id":"mfa_authenticate","is_pending":true}]},"meta":{"session_token":"sess2","is_authenticated":false}}"#)

    func testOhneZweitenFaktor() async throws {
        let net = FakeTransport([GeraetTests.instanz, angemeldet, paired])
        let store = MemoryStore()
        let session = DeviceSession(server: server, store: store, transport: net)
        let step = try await session.login(email: " erika@example.org ", password: "geheim", appVersion: "3")
        XCTAssertEqual(step, .done(sessionToken: "sess1"))
        let result = try await session.connect(sessionToken: "sess1", deviceName: "iPhone", appVersion: "3")
        XCTAssertEqual(result.device.id, 9)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/_allauth/app/v1/auth/login")
        let login = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[1].body)) as? [String: String])
        XCTAssertEqual(login["email"], "erika@example.org")
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/devices/")
        XCTAssertEqual(net.seen[2].headers["X-Session-Token"], "sess1")
        XCTAssertNil(net.seen[2].headers["Authorization"])
        let device = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[2].body)) as? [String: String])
        XCTAssertEqual(device["platform"], "ios")
        XCTAssertFalse((device["device_key"] ?? "").isEmpty)
        // Das Passwort bleibt nirgends liegen
        XCTAssertEqual(store.read(DeviceSession.tokenKey), "hpd_p")
        XCTAssertEqual(store.read(DeviceSession.deviceIdKey), "9")
        XCTAssertNotNil(store.read(DeviceSession.deviceKeyKey))
    }

    func testMitZweitemFaktor() async throws {
        let net = FakeTransport([GeraetTests.instanz, codeNoetig, angemeldet, paired])
        let session = DeviceSession(server: server, store: MemoryStore(), transport: net)
        let step = try await session.login(email: "erika@example.org", password: "geheim", appVersion: "3")
        XCTAssertEqual(step, .needsCode(sessionToken: "sess2"))
        _ = try await session.connect(sessionToken: "sess2", code: " 123 456 ", deviceName: "iPhone", appVersion: "3")
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/_allauth/app/v1/auth/2fa/authenticate")
        XCTAssertEqual(net.seen[2].headers["X-Session-Token"], "sess2")
        let code = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[2].body)) as? [String: String])
        XCTAssertEqual(code["code"], "123456")
        XCTAssertEqual(net.seen[3].headers["X-Session-Token"], "sess1")
    }

    func testFalscherCode() async throws {
        let net = FakeTransport([codeNoetig])
        let session = DeviceSession(server: server, store: MemoryStore(), transport: net)
        do {
            _ = try await session.connect(sessionToken: "sess2", code: "000000", deviceName: "iPhone", appVersion: "3")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.text, "Der Code stimmt nicht. Bitte erneut versuchen.")
        }
    }

    func testFalschesPasswort() async throws {
        let net = FakeTransport([GeraetTests.instanz, FakeTransport.json(400, #"{"status":400,"errors":[{"message":"Die E-Mail-Adresse und/oder das Passwort sind nicht korrekt.","code":"email_password_mismatch","param":"password"}]}"#)])
        let session = DeviceSession(server: server, store: MemoryStore(), transport: net)
        do {
            _ = try await session.login(email: "erika@example.org", password: "falsch", appVersion: "3")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.text, "Die E-Mail-Adresse und/oder das Passwort sind nicht korrekt.")
            XCTAssertFalse(error.mustReconnect)
        }
        XCTAssertThrowsError(try Anmeldung.step(status: 500, body: Data("{}".utf8), previous: nil)) { error in
            XCTAssertEqual((error as? ApiError)?.text, "Anmeldung fehlgeschlagen. Bitte E-Mail und Passwort prüfen.")
        }
    }

    func testPflichtfelderUndPasswortVergessen() {
        XCTAssertEqual(Anmeldung.missing(server: "", email: " ", password: ""), [.server, .email, .password])
        XCTAssertEqual(Anmeldung.missing(server: "verein.example.de", email: "a@example.org", password: "x"), [])
        XCTAssertEqual(Anmeldung.passwordReset(server: "verein.example.de")?.absoluteString, "https://verein.example.de/passwort-vergessen")
        XCTAssertNil(Anmeldung.passwordReset(server: "http://verein.example.de"))
    }
}
