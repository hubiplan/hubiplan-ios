import XCTest
@testable import HubiplanKern

/// Härtung H7: Formate wie im Server (`devices/devicekey.py`), erfundene Werte.
final class SignedFormatTests: XCTestCase {
    func testVorstandsanfrageWieDerServer() {
        let message = SignedFormat.adminMessage(
            method: "post", path: "/api/app/v1/admin/u/5/members/?q=M%C3%BCller",
            timestamp: "1700000000", body: Data(#"{"a":1}"#.utf8)
        )
        XCTAssertEqual(
            String(decoding: message, as: UTF8.self),
            "hubiplan-admin\nPOST\n/api/app/v1/admin/u/5/members/?q=M%C3%BCller\n1700000000\n"
                + "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
        )
        let empty = SignedFormat.adminMessage(method: "GET", path: "/x/", timestamp: "1", body: Data())
        XCTAssertTrue(String(decoding: empty, as: UTF8.self)
            .hasSuffix("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
    }

    func testFormat2MitKennungUndIdempotencyKey() {
        let message = SignedFormat.adminMessage(
            method: "post", path: "/x/", timestamp: "1700000000", body: Data(),
            nonce: "abcdefghijklmnopqrstuv", idempotency: "k-1"
        )
        XCTAssertEqual(
            String(decoding: message, as: UTF8.self),
            "hubiplan-admin-2\nPOST\n/x/\n1700000000\nabcdefghijklmnopqrstuv\nk-1\n"
                + "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        let nonce = SignedFormat.newNonce()
        XCTAssertEqual(nonce.count, 22)
        XCTAssertTrue(nonce.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        XCTAssertNotEqual(nonce, SignedFormat.newNonce())
    }

    func testErneuerung() {
        XCTAssertEqual(String(decoding: SignedFormat.renewMessage(deviceId: 12, challenge: "abc"), as: UTF8.self), "hubiplan-renew\n12\nabc")
    }

    func testUnterschriftPasstZumGemeldetenSchluessel() throws {
        let key = P256.Signing.PrivateKey()
        let encoded = SignedFormat.publicKey(key.publicKey)
        XCTAssertFalse(encoded.contains("="))
        let raw = try XCTUnwrap(Base64Url.decode(encoded))
        XCTAssertEqual(raw.count, 65)
        XCTAssertEqual(raw.first, 4)
        // Aus dem Punkt wieder einen Schlüssel bauen (wie der Server) und prüfen
        let rebuilt = try P256.Signing.PublicKey(x963Representation: raw)
        let message = SignedFormat.renewMessage(deviceId: 3, challenge: "aufgabe")
        let signature = try XCTUnwrap(Base64Url.decode(try SignedFormat.sign(message, with: key)))
        XCTAssertTrue(rebuilt.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: signature), for: message))
    }

    func testBase64Url() {
        XCTAssertEqual(Base64Url.encode(Data([0xfb, 0xff])), "-_8")
        XCTAssertEqual(Base64Url.decode("-_8"), Data([0xfb, 0xff]))
        XCTAssertEqual(Base64Url.decode("-_8="), Data([0xfb, 0xff]))
        XCTAssertNil(Base64Url.decode("a"))
        XCTAssertNil(Base64Url.decode("!!!!"))
    }
}
