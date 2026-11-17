import XCTest
@testable import HubiplanKern

/// Nachbau des Netzes: Antworten der Reihe nach, Anfragen werden gemerkt.
final class FakeTransport: Transport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<HttpResponse, Error>]
    private(set) var requests: [HttpRequest] = []

    init(_ answers: [Result<HttpResponse, Error>]) { self.answers = answers }

    static func json(_ status: Int, _ text: String) -> Result<HttpResponse, Error> {
        .success(HttpResponse(status: status, body: Data(text.utf8)))
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        let answer: Result<HttpResponse, Error> = lock.withLock {
            requests.append(request)
            return answers.isEmpty ? .failure(ApiError(status: 0, code: "leer")) : answers.removeFirst()
        }
        return try answer.get()
    }

    var seen: [HttpRequest] { lock.withLock { requests } }
}

final class FakeTokens: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    private(set) var renewals = 0
    var renewable = true

    init(_ token: String?) { current = token }

    func token() async -> String? { lock.withLock { current } }

    func renew(used: String) async -> String? {
        lock.withLock {
            guard renewable else { return nil }
            if current == used {
                renewals += 1
                current = used + "x"
            }
            return current
        }
    }
}

struct Kaputt: Error {}

final class ApiTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let device = #"{"id":7,"name":"iPhone von Erika","platform":"ios","current":true,"key":true}"#

    private func body(_ request: HttpRequest) throws -> [String: String] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: String])
    }

    func testSelbstauskunftOhneAnmeldung() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"product":"hubiplan","version":"2026.11.0","api_version":1,"url":"https://verein.example.de","push":[{"kind":"unifiedpush"},{"kind":"fcm","gateway":"https://push.example.org","vapid_public_key":"BEcc"}],"neu":1}"#)])
        let instance = try await Api(server: server, transport: net).instance()
        XCTAssertEqual(instance.apiVersion, 1)
        XCTAssertEqual(instance.minAppVersion, 1)
        XCTAssertEqual(instance.push.map(\.kind), ["unifiedpush", "fcm"])
        XCTAssertEqual(instance.push.last?.gateway, "https://push.example.org")
        let request = try XCTUnwrap(net.seen.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url, "https://verein.example.de/api/app/v1/instance/")
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertEqual(request.headers["Accept-Language"], "de")
    }

    func testVerbindenMeldetIosUndGeraeteschluessel() async throws {
        let net = FakeTransport([FakeTransport.json(201, #"{"token":"hpd_erfunden","device":\#(device),"user":{"email":"erika@example.org","display":"Erika Musterfrau"}}"#)])
        let paired = try await Api(server: server, transport: net, language: "en")
            .pair(code: "abc", deviceName: "iPhone von Erika", appVersion: "0.1.0", deviceKey: "BEcc")
        XCTAssertEqual(paired.token, "hpd_erfunden")
        XCTAssertEqual(paired.device.platform, "ios")
        XCTAssertEqual(paired.device.key, true)
        XCTAssertEqual(paired.user.display, "Erika Musterfrau")
        let request = try XCTUnwrap(net.seen.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://verein.example.de/api/app/v1/pair/")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.headers["Accept-Language"], "en")
        XCTAssertEqual(try body(request), [
            "code": "abc", "login_link": "", "name": "iPhone von Erika",
            "platform": "ios", "app_version": "0.1.0", "device_key": "BEcc", "verifier": "",
        ])
    }

    func testKontoMitZugaengenAelterUndNeuerInstanzen() async throws {
        let net = FakeTransport([FakeTransport.json(200, #"{"user":{"email":"erika@example.org","display":"Erika Musterfrau"},"device":\#(device),"portal":[{"id":3,"club_name":"Schützenverein Musterstadt","modules":["events","meetings"],"member_kind":"organization","member_name":"Muster GmbH"},{"id":4,"club_name":"Musikverein Musterdorf","events_enabled":false}]}"#)])
        let me = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).me()
        XCTAssertEqual(net.seen.first?.headers["Authorization"], "Bearer hpd_a")
        XCTAssertEqual(me.portal.count, 2)
        XCTAssertTrue(me.portal[0].has(module: "meetings"))
        XCTAssertFalse(me.portal[0].has(module: "music"))
        XCTAssertEqual(me.portal[0].memberName, "Muster GmbH")
        XCTAssertNil(me.portal[1].modules)
        XCTAssertFalse(me.portal[1].has(module: "events", fallback: me.portal[1].eventsEnabled))
        XCTAssertEqual(me.portal[1].memberKind, "person")
    }

    func testFehlerMitKennung() async throws {
        let net = FakeTransport([FakeTransport.json(401, #"{"detail":"Gerät ist abgemeldet.","code":"device_not_authenticated"}"#)])
        do {
            _ = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).me()
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 401)
            XCTAssertTrue(error.mustReconnect)
            XCTAssertEqual(error.message, "Gerät ist abgemeldet.")
        }
    }

    func testOhneNetzUndKaputteAntwort() async throws {
        let offline = FakeTransport([.failure(Kaputt())])
        do {
            _ = try await Api(server: server, transport: offline).instance()
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error, ApiError(status: 0, code: "offline"))
        }
        let html = FakeTransport([FakeTransport.json(200, "<html>Wartung</html>")])
        do {
            _ = try await Api(server: server, transport: html).instance()
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.code, "format")
        }
    }

    /// 401 device_renew: Schlüssel erneuern und die Anfrage genau einmal wiederholen.
    func testErneuertUndWiederholtEinmal() async throws {
        let renewDue = FakeTransport.json(401, #"{"code":"device_renew"}"#)
        let ok = FakeTransport.json(200, #"{"user":{"email":"erika@example.org","display":"Erika"},"device":\#(device),"portal":[]}"#)
        let net = FakeTransport([renewDue, ok])
        let tokens = FakeTokens("hpd_a")
        let me = try await Api(server: server, transport: net, tokens: tokens).me()
        XCTAssertEqual(me.portal.count, 0)
        XCTAssertEqual(tokens.renewals, 1)
        XCTAssertEqual(net.seen.map { $0.headers["Authorization"] }, ["Bearer hpd_a", "Bearer hpd_ax"])

        // Zweimal hintereinander device_renew: nie als 401 nach oben geben
        let loop = FakeTransport([renewDue, renewDue])
        do {
            _ = try await Api(server: server, transport: loop, tokens: FakeTokens("hpd_a")).me()
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error, ApiError(status: 0, code: "renew_failed"))
        }
        XCTAssertEqual(loop.seen.count, 2)

        let stuck = FakeTokens("hpd_a")
        stuck.renewable = false
        do {
            _ = try await Api(server: server, transport: FakeTransport([renewDue]), tokens: stuck).me()
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.code, "renew_failed")
        }
    }

    /// Erneuern (H7): Aufgabe holen, mit dem Geräteschlüsselpaar unterschreiben.
    func testErneuernUnterschreibtDieAufgabe() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"challenge":"aufgabe-1"}"#),
            FakeTransport.json(201, #"{"token":"hpd_neu","device":\#(device)}"#),
        ])
        let key = P256.Signing.PrivateKey()
        let renewed = try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).renew(deviceId: 7, key: key)
        XCTAssertEqual(renewed.token, "hpd_neu")
        XCTAssertEqual(net.seen.count, 2)
        XCTAssertNil(net.seen[0].body)
        let sent = try body(net.seen[1])
        XCTAssertEqual(sent["challenge"], "aufgabe-1")
        let signature = try P256.Signing.ECDSASignature(derRepresentation: try XCTUnwrap(Base64Url.decode(try XCTUnwrap(sent["signature"]))))
        XCTAssertTrue(key.publicKey.isValidSignature(signature, for: Data("hubiplan-renew\n7\naufgabe-1".utf8)))
    }

    /// Die Erneuerung selbst erneuert nicht noch einmal (sonst Schleife).
    func testErneuernLoestKeineErneuerungAus() async throws {
        let net = FakeTransport([FakeTransport.json(401, #"{"code":"device_renew"}"#)])
        let tokens = FakeTokens("hpd_a")
        do {
            _ = try await Api(server: server, transport: net, tokens: tokens).renew(deviceId: 7, key: P256.Signing.PrivateKey())
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 401)
        }
        XCTAssertEqual(tokens.renewals, 0)
        XCTAssertEqual(net.seen.count, 1)
    }
}
