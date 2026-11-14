import XCTest
@testable import HubiplanKern

final class WebPushTests: XCTestCase {
    // Erzeugt mit dem Backend (hubiplan devices/webpush.py) mit festem Schlüssel und Salz;
    // dieselbe Nachricht prüft die Android-App (WebPushCryptoTest).
    private let keys = "EjRWeJCrze8SNFZ4kKvN7xI0VniQq83vEjRWeJCrze8.AAECAwQFBgcICQoLDA0ODw"
    private let p256dh = "BEccPnWMSQQoW7p-UxGO0PUkresHV9Jb0vjnsNdt-nFM3VIPesqKi5F6zDf1HejwybvjrYWDgucC3CWhLQn3qFg"
    private let body =
        "ZGVmZ2hpamtsbW5vcHFycwAAEABBBOCylUStPA_diaF2Pd-mMs58Gx6nYaDlC1G3a_rvVxeeUV3m1tR0QIqrhT6gLlCDlW3k0Oqotizgb-ul4UOoU5NCAlEYiVuMVs9phhYNNenEule1N6YXgV1oCKR2xrRdiJ-XZKA7jF7ohef7Dvasme1jobyby3vme5EYzDwqS2CadfdjWKnEy2UwkMJk3qwZKU32gusX1CWgHfenri6-4xvBrviaLgeTXqIoHnz9"

    func testEntschluesseltNachrichtDesBackends() throws {
        let k = try XCTUnwrap(PushKeys.parse(keys))
        XCTAssertEqual(k.p256dh, p256dh)
        let plain = try WebPushCrypto.decrypt(try XCTUnwrap(Base64Url.decode(body)), keys: k)
        XCTAssertEqual(
            String(decoding: plain, as: UTF8.self),
            #"{"v":1,"t":"circular","title":"Antreten","text":"Heute 18 Uhr am Zelt – bitte pünktlich"}"#
        )
    }

    func testFalscherSchluesselScheitert() throws {
        let data = try XCTUnwrap(Base64Url.decode(body))
        XCTAssertThrowsError(try WebPushCrypto.decrypt(data, keys: PushKeys.generate())) {
            XCTAssertTrue($0 is PushDecryptError)
        }
    }

    /// Ungültige Punkte, Präfixe und Längen enden immer als PushDecryptError.
    func testUngueltigeNachrichtenBleibenInDerFehlergrenze() throws {
        let k = try XCTUnwrap(PushKeys.parse(keys))
        let original = [UInt8](try XCTUnwrap(Base64Url.decode(body)))
        func withSender(_ sender: [UInt8]) -> [UInt8] {
            Array(original[0..<21]) + sender + Array(original[(21 + 65)...])
        }
        var recordSize1 = original
        recordSize1.replaceSubrange(16..<20, with: [0, 0, 0, 1])
        var badTag = original
        badTag[badTag.count - 1] &+= 1
        let cases: [[UInt8]] = [
            withSender([0x04] + [UInt8](repeating: 0, count: 64)), // Punkt nicht auf der Kurve
            withSender([0x02] + [UInt8](repeating: 0, count: 64)), // falsches Präfix
            withSender([0x04] + [UInt8](repeating: 0xFF, count: 64)), // außerhalb des Feldes
            Array(original[0..<50]), // zu kurz
            original + [UInt8](repeating: 0, count: WebPushCrypto.maxBody + 1 - original.count), // zu groß
            recordSize1, // Datensatzgröße 1
            badTag, // GCM-Tag falsch
            [],
        ]
        for c in cases {
            XCTAssertThrowsError(try WebPushCrypto.decrypt(Data(c), keys: k)) {
                XCTAssertTrue($0 is PushDecryptError)
            }
        }
        // Danach geht eine gültige Nachricht weiter durch; auch als Ausschnitt eines größeren Puffers
        XCTAssertNoThrow(try WebPushCrypto.decrypt(Data(original), keys: k))
        let slice = Data([9, 9] + original).dropFirst(2)
        XCTAssertNoThrow(try WebPushCrypto.decrypt(slice, keys: k))
    }

    func testSchluesselSpeichernUndLaden() throws {
        let k = PushKeys.generate()
        let again = try XCTUnwrap(PushKeys.parse(k.serialize()))
        XCTAssertEqual(k.p256dh, again.p256dh)
        XCTAssertEqual(k.authB64, again.authB64)
        XCTAssertEqual(Base64Url.decode(k.p256dh)?.count, 65)
        XCTAssertEqual(Base64Url.decode(k.authB64)?.count, 16)
        XCTAssertNil(PushKeys.parse("kein.schluessel"))
        XCTAssertNil(PushKeys.parse(""))
    }

    func testPushNachrichtLesen() throws {
        let m = try XCTUnwrap(PushMessage.parse(#"{"v":1,"t":"circular","access":3,"id":9,"kind":"short","title":"T","text":"x","from":"Zug 1"}"#))
        XCTAssertEqual(m.access, 3)
        XCTAssertEqual(m.id, 9)
        XCTAssertEqual(m.type, "circular")
        XCTAssertEqual(m.from, "Zug 1")
        XCTAssertFalse(m.rsvp)
        XCTAssertEqual(PushMessage.parse(#"{"v":1,"t":"sync"}"#)?.type, "sync")
        let invite = try XCTUnwrap(PushMessage.parse(#"{"v":1,"t":"event","access":3,"id":4,"kind":"invite","rsvp":true,"maybe":true,"neu":"egal"}"#))
        XCTAssertTrue(invite.rsvp && invite.maybe)
        XCTAssertNil(PushMessage.parse("kein json"))
    }
}
