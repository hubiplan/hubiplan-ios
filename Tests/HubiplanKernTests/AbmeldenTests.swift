import Foundation
import XCTest
@testable import HubiplanKern

/// Verbindung trennen meldet das Gerät auch beim Server ab (Gesamtaudit 15.11., APP-02),
/// wie Android: Push abmelden, Gerät abmelden, danach lokal alles vergessen; ohne Netz oder
/// bei hängender Instanz trotzdem lokal löschen, ohne lange zu warten.
final class AbmeldenTests: XCTestCase {
    private let server = "https://verein.example.de"

    private func verbunden(_ net: Transport) -> (DeviceSession, MemoryStore) {
        let store = MemoryStore()
        store.write(DeviceSession.tokenKey, "hpd_a")
        store.write(DeviceSession.deviceIdKey, "7")
        store.write(DeviceSession.deviceKeyKey, "schluessel")
        return (DeviceSession(server: server, store: store, transport: net), store)
    }

    func testMeldetPushUndGeraetAb() async {
        let net = FakeTransport([FakeTransport.json(204, ""), FakeTransport.json(204, "")])
        let (session, store) = verbunden(net)
        await session.signOut()
        let wege = net.seen.map { "\($0.method) \($0.url)" }
        XCTAssertEqual(wege, [
            "DELETE https://verein.example.de/api/app/v1/devices/current/push/",
            "DELETE https://verein.example.de/api/app/v1/devices/7/",
        ])
        XCTAssertNil(store.read(DeviceSession.tokenKey))
        XCTAssertNil(store.read(DeviceSession.deviceKeyKey))
    }

    func testOhneNetzTrotzdemLokalGeloescht() async {
        let net = FakeTransport([])  // jede Anfrage scheitert
        let (session, store) = verbunden(net)
        await session.signOut()
        XCTAssertNil(store.read(DeviceSession.tokenKey))
        XCTAssertNil(store.read(DeviceSession.deviceIdKey))
    }

    func testHaengendeInstanzHaeltNichtAuf() async {
        let (session, store) = verbunden(HaengendesNetz())
        let start = Date()
        await session.signOut(timeout: 0.3)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertNil(store.read(DeviceSession.tokenKey))
    }
}

/// Netz, das nie antwortet (bis zum Abbruch des Tests).
final class HaengendesNetz: Transport, @unchecked Sendable {
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return HttpResponse(status: 204, body: Data())
    }
}
