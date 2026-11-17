import Foundation
import XCTest
@testable import HubiplanKern

/// Herkunft des Geräteschlüsselpaars (Gesamtaudit 15.11., APP-03). Der Weg über die Secure
/// Enclave lässt sich nur auf einem Gerät prüfen; hier: die Abstraktion, Software-Schlüssel und
/// dass ältere Verbindungen ihren Software-Schlüssel behalten.
final class GeraeteschluesselTests: XCTestCase {
    /// Nachbau einer Hardware-Quelle: merkt sich, dass sie benutzt wurde
    final class FakeHardware: DeviceKeyStore, @unchecked Sendable {
        var created = 0
        var hardwareAvailable: Bool { true }
        func create() throws -> (signer: DeviceKeySigner, stored: String) {
            created += 1
            let (signer, stored) = try SoftwareDeviceKeys().create()
            return (Hart(inner: signer), "hw:" + stored)
        }
        func load(_ stored: String) -> DeviceKeySigner? {
            guard stored.hasPrefix("hw:") else { return nil }
            return SoftwareDeviceKeys().load(String(stored.dropFirst(3))).map { Hart(inner: $0) }
        }
    }

    struct Hart: DeviceKeySigner {
        let inner: DeviceKeySigner
        var publicKey: String { inner.publicKey }
        var inHardware: Bool { true }
        func sign(_ message: Data) throws -> String { try inner.sign(message) }
    }

    private let server = "https://verein.example.de"

    func testSoftwareSchluesselUnterschreibtPruefbar() throws {
        let (signer, stored) = try SoftwareDeviceKeys().create()
        let loaded = try XCTUnwrap(SoftwareDeviceKeys().load(stored))
        XCTAssertEqual(loaded.publicKey, signer.publicKey)
        let message = Data("hubiplan-renew\n7\naufgabe".utf8)
        let der = try XCTUnwrap(Base64Url.decode(try loaded.sign(message)))
        let raw = try XCTUnwrap(Base64Url.decode(signer.publicKey))
        let pub = try P256.Signing.PublicKey(x963Representation: raw)
        XCTAssertTrue(pub.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: der), for: message))
    }

    func testNeueVerbindungNutztDieQuelle() async throws {
        let device = #"{"id":7,"name":"iPhone","platform":"ios","current":true,"key":true}"#
        let net = FakeTransport([
            // Selbstauskunft vor dem Verbinden (Mindestversion, APP-11)
            FakeTransport.json(200, #"{"product":"HUBIplan","api_version":1}"#),
            FakeTransport.json(201, #"{"token":"hpd_a","device":\#(device),"user":{"email":"erika@example.org","display":"Erika"}}"#),
        ])
        let store = MemoryStore()
        let hardware = FakeHardware()
        let session = DeviceSession(server: server, store: store, transport: net, keys: hardware)
        _ = try await session.connect(code: "abc", deviceName: "iPhone", appVersion: "1")
        XCTAssertEqual(hardware.created, 1)
        XCTAssertTrue(store.read(DeviceSession.deviceKeyKey)?.hasPrefix("hw:") ?? false)
        let soft = await session.usesSoftwareKey
        XCTAssertFalse(soft)
    }

    func testAlteVerbindungBehaeltSoftwareSchluessel() async throws {
        let store = MemoryStore()
        let (_, stored) = try SoftwareDeviceKeys().create()
        store.write(DeviceSession.deviceKeyKey, stored)
        let session = DeviceSession(server: server, store: store, transport: FakeTransport([]), keys: FakeHardware())
        let signer = await session.signer()
        XCTAssertNotNil(signer)  // Rückfall auf den Software-Schlüssel
        let soft = await session.usesSoftwareKey
        XCTAssertTrue(soft)
    }

    func testOhneSecureEnclaveKeinHinweis() async throws {
        // Simulator oder Gerät ohne Secure Enclave: Neuverbinden änderte nichts
        let store = MemoryStore()
        let (_, stored) = try SoftwareDeviceKeys().create()
        store.write(DeviceSession.deviceKeyKey, stored)
        let session = DeviceSession(server: server, store: store, transport: FakeTransport([]), keys: SoftwareDeviceKeys())
        let soft = await session.usesSoftwareKey
        XCTAssertFalse(soft)
    }
}
