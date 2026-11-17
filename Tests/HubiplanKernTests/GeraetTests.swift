import XCTest
@testable import HubiplanKern

final class MemoryStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(_ key: String) -> String? { lock.withLock { values[key] } }
    func write(_ key: String, _ value: String?) { lock.withLock { values[key] = value } }
}

final class GeraetTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let device = #"{"id":7,"name":"iPhone von Erika","platform":"ios","current":true,"key":true}"#

    /// Selbstauskunft vor dem Verbinden (APP-11)
    static let instanz = FakeTransport.json(200, #"{"product":"HUBIplan","api_version":1,"min_app_versions":{"android":5,"ios":1}}"#)

    private func paired(_ token: String) -> Result<HttpResponse, Error> {
        FakeTransport.json(201, #"{"token":"\#(token)","device":\#(device),"user":{"email":"erika@example.org","display":"Erika Musterfrau"}}"#)
    }

    func testVerbindenMerktSchluesselUndGeraet() async throws {
        let net = FakeTransport([Self.instanz, paired("hpd_a")])
        let store = MemoryStore()
        let session = DeviceSession(server: server, store: store, transport: net)
        let before = await session.connected
        XCTAssertFalse(before)
        let result = try await session.connect(code: "abc", deviceName: "iPhone von Erika", appVersion: "3")
        XCTAssertEqual(result.user.display, "Erika Musterfrau")
        let token = await session.token()
        XCTAssertEqual(token, "hpd_a")
        XCTAssertEqual(store.read(DeviceSession.deviceIdKey), "7")
        // Der gemeldete öffentliche Schlüssel gehört zum gespeicherten privaten
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[1].body)) as? [String: String])
        let raw = try XCTUnwrap(Base64Url.decode(try XCTUnwrap(store.read(DeviceSession.deviceKeyKey))))
        let key = try P256.Signing.PrivateKey(rawRepresentation: raw)
        XCTAssertEqual(sent["device_key"], SignedFormat.publicKey(key.publicKey))
        XCTAssertEqual(sent["platform"], "ios")
        XCTAssertNil(net.seen[1].headers["Authorization"])

        await session.forget()
        let after = await session.connected
        XCTAssertFalse(after)
        XCTAssertNil(store.read(DeviceSession.deviceKeyKey))
    }

    func testFehlgeschlagenesVerbindenMerktNichts() async throws {
        let store = MemoryStore()
        let session = DeviceSession(server: server, store: store, transport: FakeTransport([Self.instanz, FakeTransport.json(400, #"{"detail":"Der Code ist abgelaufen."}"#)]))
        do {
            _ = try await session.connect(code: "alt", deviceName: "iPhone", appVersion: "3")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.text, "Der Code ist abgelaufen.")
        }
        XCTAssertNil(store.read(DeviceSession.tokenKey))
        XCTAssertNil(store.read(DeviceSession.deviceKeyKey))
    }

    /// 401 device_renew mitten in einer Anfrage: erneuern, neuen Schlüssel merken, wiederholen.
    func testErneuertUeberDasGeraet() async throws {
        let net = FakeTransport([
            Self.instanz,
            paired("hpd_a"),
            FakeTransport.json(401, #"{"code":"device_renew"}"#),
            FakeTransport.json(200, #"{"challenge":"aufgabe"}"#),
            FakeTransport.json(201, #"{"token":"hpd_b","device":\#(device)}"#),
            FakeTransport.json(200, #"{"items":[]}"#),
        ])
        let store = MemoryStore()
        let session = DeviceSession(server: server, store: store, transport: net)
        _ = try await session.connect(code: "abc", deviceName: "iPhone", appVersion: "3")
        let events = try await session.api().events(accessId: 3, from: "2026-11-01", to: "2026-12-01")
        XCTAssertEqual(events.count, 0)
        XCTAssertEqual(store.read(DeviceSession.tokenKey), "hpd_b")
        XCTAssertEqual(net.seen.map { $0.headers["Authorization"] ?? "-" }, ["-", "Bearer hpd_a", "Bearer hpd_a", "Bearer hpd_a", "Bearer hpd_b"])
        // Schon erneuert: ein zweiter Aufruf mit dem alten Schlüssel erneuert nicht noch einmal
        let again = await session.renew(used: "hpd_a")
        XCTAssertEqual(again, "hpd_b")
        XCTAssertEqual(net.seen.count, 5)
    }

    func testOhneSchluesselpaarKeineErneuerung() async {
        let store = MemoryStore()
        store.write(DeviceSession.tokenKey, "hpd_a")
        let net = FakeTransport([])
        let session = DeviceSession(server: server, store: store, transport: net)
        let result = await session.renew(used: "hpd_a")
        XCTAssertNil(result)
        XCTAssertEqual(net.seen.count, 0)
    }
}
