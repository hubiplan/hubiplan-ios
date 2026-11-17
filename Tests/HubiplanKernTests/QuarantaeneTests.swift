import XCTest
@testable import HubiplanKern

/// Entwürfe bei Abmeldung durch den Server in die Quarantäne statt löschen (Gesamtaudit 15.11.,
/// APP-04), gleiche Fälle wie Android (LocalAccountData): verschlüsselt mit eigenem Schlüssel,
/// an Instanz und Konto gebunden, nach erneutem Verbinden zurück, für ein anderes Konto nicht,
/// nach 120 Tagen abgelaufen.
final class QuarantaeneTests: XCTestCase {
    private let server = "https://verein.example.de"

    private func box() -> DraftBox { DraftBox(files: MemoryFiles(), secrets: MemoryStore()) }

    private struct Beleg: Codable, Equatable { var text: String }

    private func gefuellt() -> DraftBox {
        let b = box()
        XCTAssertTrue(b.seal(Beleg(text: "Getränke"), "k-1" + DraftBox.ending))
        XCTAssertTrue(b.seal(Beleg(text: "Quittung"), "q-1" + DraftBox.receiptEnding))
        return b
    }

    func testZurueckNachErneutemVerbinden() {
        let alt = gefuellt()
        let quarantaene = box()
        let owner = DraftQuarantine.Owner(server: server, email: "Erika@Example.org", since: Date())
        XCTAssertEqual(DraftQuarantine.retire(alt, into: quarantaene, owner: owner, files: quarantaene.files), 2)
        alt.clear()
        // Verschlüsselt mit dem Schlüssel der Quarantäne, nicht dem des alten Kontos
        let roh = quarantaene.files.read("k-1" + DraftBox.ending) ?? Data()
        XCTAssertFalse(String(decoding: roh, as: UTF8.self).contains("Getränke"))
        let neu = box()
        XCTAssertEqual(DraftQuarantine.adopt(quarantaene, into: neu, server: server, email: "erika@example.org"), 2)
        XCTAssertEqual(neu.unseal(Beleg.self, "k-1" + DraftBox.ending), Beleg(text: "Getränke"))
        XCTAssertTrue(quarantaene.files.names().isEmpty)
    }

    func testAnderesKontoBekommtNichts() {
        let quarantaene = box()
        let owner = DraftQuarantine.Owner(server: server, email: "erika@example.org", since: Date())
        DraftQuarantine.retire(gefuellt(), into: quarantaene, owner: owner, files: quarantaene.files)
        let fremd = box()
        XCTAssertEqual(DraftQuarantine.adopt(quarantaene, into: fremd, server: server, email: "max@example.org"), 0)
        XCTAssertEqual(DraftQuarantine.adopt(quarantaene, into: fremd, server: "https://andere.example.de", email: "erika@example.org"), 0)
        XCTAssertTrue(fremd.files.names().isEmpty)
        XCTAssertNotEqual(
            DraftQuarantine.id(server: server, email: "erika@example.org"),
            DraftQuarantine.id(server: server, email: "max@example.org")
        )
    }

    func testAblauf() {
        let quarantaene = box()
        let alt = Date().addingTimeInterval(-121 * 24 * 3600)
        DraftQuarantine.retire(gefuellt(), into: quarantaene, owner: .init(server: server, email: "e@example.org", since: alt), files: quarantaene.files)
        XCTAssertTrue(DraftQuarantine.expired(quarantaene.files))
        XCTAssertFalse(DraftQuarantine.expired(quarantaene.files, now: alt.addingTimeInterval(24 * 3600)))
    }
}
