import XCTest
@testable import HubiplanKern

final class PushTests: XCTestCase {
    private let server = "https://verein.example.de"
    private let vapid = "BEccPnWMSQQoW7p-UxGO0PUkresHV9Jb0vjnsNdt-nFM3VIPesqKi5F6zDf1HejwybvjrYWDgucC3CWhLQn3qFg"
    private let token = String(repeating: "ab12", count: 16)

    private func instance(_ push: String) -> String {
        #"{"product":"hubiplan","api_version":1,"push":\#(push)}"#
    }

    private func way(kind: String = "apns", gateway: String = "https://push.example.org", key: String? = nil) throws -> PushWay {
        let json = #"{"kind":"\#(kind)","gateway":"\#(gateway)","vapid_public_key":"\#(key ?? vapid)"}"#
        return try JSONDecoder().decode(PushWay.self, from: Data(json.utf8))
    }

    func testKennungWieImGateway() {
        // Erste 16 Hex-Zeichen von SHA-256 über den rohen Schlüssel (wie pushgateway key_id)
        XCTAssertEqual(ApplePush.keyId(vapidPublicKey: vapid), "fd1fee555a7ccac8")
        XCTAssertNil(ApplePush.keyId(vapidPublicKey: "AAAA"))
        XCTAssertNil(ApplePush.keyId(vapidPublicKey: "kein base64 !"))
    }

    func testEndpunkt() throws {
        XCTAssertEqual(ApplePush.tokenText(Data([0xAB, 0x12, 0x00])), "ab1200")
        XCTAssertEqual(
            ApplePush.endpoint(way: try way(gateway: "https://push.example.org/"), deviceToken: token),
            "https://push.example.org/apns/\(token)/fd1fee555a7ccac8"
        )
        // Nur https, nur der Apple-Weg, nur Hex in Kleinbuchstaben und in gültiger Länge
        XCTAssertNil(ApplePush.endpoint(way: try way(gateway: "http://push.example.org"), deviceToken: token))
        XCTAssertNil(ApplePush.endpoint(way: try way(kind: "fcm"), deviceToken: token))
        XCTAssertNil(ApplePush.endpoint(way: try way(key: "AAAA"), deviceToken: token))
        XCTAssertNil(ApplePush.endpoint(way: try way(), deviceToken: "ab12"))
        XCTAssertNil(ApplePush.endpoint(way: try way(), deviceToken: token.uppercased()))
        XCTAssertNil(ApplePush.endpoint(way: try way(), deviceToken: String(repeating: "/", count: 64)))
    }

    func testAnmeldenBeiDerInstanz() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, instance(#"[{"kind":"unifiedpush","vapid_public_key":"\#(vapid)"},{"kind":"apns","gateway":"https://push.example.org","vapid_public_key":"\#(vapid)"}]"#)),
            FakeTransport.json(200, "{}"),
            FakeTransport.json(200, instance(#"[{"kind":"unifiedpush","vapid_public_key":"\#(vapid)"},{"kind":"fcm","gateway":"https://push.example.org","vapid_public_key":"\#(vapid)"}]"#)),
        ])
        let store = MemoryStore()
        store.write(DeviceSession.tokenKey, "hpd_a")
        let session = DeviceSession(server: server, store: store, transport: net)
        let registered = try await session.registerPush(deviceToken: token)
        XCTAssertTrue(registered)
        XCTAssertEqual(net.seen[1].method, "PUT")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/devices/current/push/")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[1].body)) as? [String: String])
        XCTAssertEqual(sent["kind"], "apns")
        XCTAssertEqual(sent["endpoint"], "https://push.example.org/apns/\(token)/fd1fee555a7ccac8")
        // Die Schlüssel bleiben auf dem Gerät und sind beim nächsten Mal dieselben
        let keys = await session.pushKeys()
        XCTAssertEqual(sent["p256dh"], keys.p256dh)
        XCTAssertEqual(sent["auth"], keys.authB64)
        XCTAssertNotNil(store.read(ApplePush.keysKey))
        // Instanz ohne Apple-Weg: nichts melden
        let none = try await session.registerPush(deviceToken: token)
        XCTAssertFalse(none)
        XCTAssertEqual(net.seen.count, 3)
        await session.forget()
        XCTAssertNil(store.read(ApplePush.keysKey))
    }

    func testAbmelden() async throws {
        let net = FakeTransport([FakeTransport.json(200, "{}")])
        try await Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).clearPush()
        XCTAssertEqual(net.seen.first?.method, "DELETE")
        XCTAssertEqual(net.seen.first?.url, "https://verein.example.de/api/app/v1/devices/current/push/")
    }

    func testNachrichtVonAppleOeffnen() throws {
        // Dieselbe Nachricht wie in WebPushTests, wie das Gateway sie in „b“ legt (base64)
        let keys = try XCTUnwrap(PushKeys.parse("EjRWeJCrze8SNFZ4kKvN7xI0VniQq83vEjRWeJCrze8.AAECAwQFBgcICQoLDA0ODw"))
        let b = "ZGVmZ2hpamtsbW5vcHFycwAAEABBBOCylUStPA/diaF2Pd+mMs58Gx6nYaDlC1G3a/rvVxeeUV3m1tR0QIqrhT6gLlCDlW3k0Oqotizgb+ul4UOoU5NCAlEYiVuMVs9phhYNNenEule1N6YXgV1oCKR2xrRdiJ+XZKA7jF7ohef7Dvasme1jobyby3vme5EYzDwqS2CadfdjWKnEy2UwkMJk3qwZKU32gusX1CWgHfenri6+4xvBrviaLgeTXqIoHnz9"
        let message = try XCTUnwrap(ApplePush.open(b: b, keys: keys))
        XCTAssertEqual(message.type, "circular")
        XCTAssertEqual(message.title, "Antreten")
        XCTAssertNil(ApplePush.open(b: b, keys: PushKeys.generate()))
        XCTAssertNil(ApplePush.open(b: "kein base64 !", keys: keys))
    }
}
