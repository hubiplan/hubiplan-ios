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
        XCTAssertEqual(DraftQuarantine.retire(alt, into: quarantaene, owner: owner), 2)
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
        DraftQuarantine.retire(gefuellt(), into: quarantaene, owner: owner)
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
        DraftQuarantine.retire(gefuellt(), into: quarantaene, owner: .init(server: server, email: "e@example.org", since: alt))
        XCTAssertTrue(DraftQuarantine.expired(quarantaene.files))
        XCTAssertFalse(DraftQuarantine.expired(quarantaene.files, now: alt.addingTimeInterval(24 * 3600)))
    }

    // Rückfrage nach 90 Tagen mit Export (Fachfrage FQ24), Fälle wie Android

    private func alteQuarantaene(tage: Int, email: String = "e@example.org") -> DraftBox {
        let q = box()
        let since = Date().addingTimeInterval(-Double(tage) * 24 * 3600)
        DraftQuarantine.retire(gefuellt(), into: q, owner: .init(server: server, email: email, since: since))
        return q
    }

    func testRueckfrageErstNach90Tagen() {
        let jung = alteQuarantaene(tage: 10)
        let alt = alteQuarantaene(tage: 91)
        XCTAssertEqual(DraftQuarantine.staleCount([jung]), 0)
        XCTAssertEqual(DraftQuarantine.staleCount([jung, alt]), 2)
        let ende = try? XCTUnwrap(DraftQuarantine.finalDeletion([jung, alt]))
        let erwartet = Date().addingTimeInterval(-91 * 24 * 3600 + 120 * 24 * 3600)
        XCTAssertEqual(ende?.timeIntervalSince1970 ?? 0, erwartet.timeIntervalSince1970, accuracy: 5)
        XCTAssertNil(DraftQuarantine.finalDeletion([jung]))
    }

    func testExportEnthaeltNurAlteVorgaenge() throws {
        Texte.language = "de"
        let jung = alteQuarantaene(tage: 10, email: "jung@example.org")
        let alt = alteQuarantaene(tage: 91, email: "alt@example.org")
        let konten: [DraftQuarantine.Konto] = [(server, "jung@example.org"), (server, "ALT@example.org")]
        let (data, anzahl) = try XCTUnwrap(DraftQuarantine.exportStale([jung, alt], accounts: konten))
        XCTAssertEqual(anzahl, 2)
        let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try XCTUnwrap(doc["vorgaenge"] as? [[String: Any]])
        XCTAssertEqual(Set(items.compactMap { $0["konto"] as? String }), ["alt@example.org"])
        XCTAssertEqual(Set(items.compactMap { $0["art"] as? String }), ["entwuerfe", "quittungen"])
        XCTAssertTrue((doc["hinweis"] as? String ?? "").contains("bitte löschen"))
        XCTAssertNil(DraftQuarantine.exportStale([jung], accounts: konten))
    }

    /// Sicherheitsprüfung 26.11.2026, SEC-02: Export nur für gerade verbundene Konten.
    func testExportNurFuerVerbundeneKonten() throws {
        Texte.language = "de"
        let eigen = alteQuarantaene(tage: 91, email: "kasse@example.org")
        let fremd = alteQuarantaene(tage: 91, email: "anderer@example.org")
        let herrenlos = alteQuarantaene(tage: 91, email: "weg@example.org")
        herrenlos.files.delete(DraftQuarantine.ownerName)
        ordner(herrenlos).changedAt = Date().addingTimeInterval(-91 * tag)
        let boxen = [eigen, fremd, herrenlos]
        let konten: [DraftQuarantine.Konto] = [(server.uppercased().replacingOccurrences(of: "HTTPS", with: "https"), "Kasse@Example.org")]

        XCTAssertEqual(DraftQuarantine.exportableStaleCount(boxen, accounts: konten), 2)
        let (data, anzahl) = try XCTUnwrap(DraftQuarantine.exportStale(boxen, accounts: konten))
        XCTAssertEqual(anzahl, 2)
        let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try XCTUnwrap(doc["vorgaenge"] as? [[String: Any]])
        XCTAssertEqual(Set(items.compactMap { $0["konto"] as? String }), ["kasse@example.org"])

        // Niemand verbunden, anderes Konto, andere Instanz oder leere E-Mail: nichts
        let ohne: [[DraftQuarantine.Konto]] = [
            [], [(server, "dritte@example.org")], [("https://andere.example.de", "kasse@example.org")], [(server, "")],
        ]
        for konten in ohne {
            XCTAssertEqual(DraftQuarantine.exportableStaleCount(boxen, accounts: konten), 0)
            XCTAssertNil(DraftQuarantine.exportStale(boxen, accounts: konten))
        }
        // Die Rückfrage zählt weiter alle alten Vorgänge (Löschen bleibt möglich)
        XCTAssertEqual(DraftQuarantine.staleCount(boxen), 6)
    }

    // konto.json zuerst; ohne lesbares konto.json zählt das Ordnerdatum, nie sofort löschen

    private let tag: Double = 24 * 3600

    private func ordner(_ q: DraftBox) -> MemoryFiles { q.files as! MemoryFiles }

    func testKontoDateiVorDenEntwuerfen() {
        let q = box()
        DraftQuarantine.retire(gefuellt(), into: q, owner: .init(server: server, email: "e@example.org", since: Date()))
        // Endet die App mitten im Verschieben, hat die Quarantäne trotzdem einen Eigentümer
        XCTAssertEqual(q.files.names().first, DraftQuarantine.ownerName)
        XCTAssertEqual(q.files.names().count, 3)
    }

    func testLeereQuarantaeneOhneKontoDatei() {
        let q = box()
        XCTAssertEqual(DraftQuarantine.retire(box(), into: q, owner: .init(server: server, email: "e@example.org", since: Date())), 0)
        XCTAssertTrue(q.files.names().isEmpty)
    }

    func testOhneKontoDateiNichtSofortGeloescht() {
        let q = alteQuarantaene(tage: 0)
        q.files.delete(DraftQuarantine.ownerName)
        // Datum unbekannt: behalten
        XCTAssertFalse(DraftQuarantine.expired(q.files))
        XCTAssertEqual(DraftQuarantine.staleCount([q]), 0)
        // Ordner kürzlich geändert: behalten
        ordner(q).changedAt = Date().addingTimeInterval(-10 * tag)
        XCTAssertFalse(DraftQuarantine.expired(q.files))
        XCTAssertEqual(DraftQuarantine.staleCount([q]), 0)
    }

    func testUnlesbareKontoDateiNichtSofortGeloescht() {
        let q = alteQuarantaene(tage: 0)
        XCTAssertTrue(q.files.write(DraftQuarantine.ownerName, Data("kaputt".utf8)))
        XCTAssertNil(DraftQuarantine.owner(q.files))
        ordner(q).changedAt = Date().addingTimeInterval(-tag)
        XCTAssertFalse(DraftQuarantine.expired(q.files))
    }

    func testOhneKontoDateiAblaufNachOrdnerdatum() throws {
        let q = alteQuarantaene(tage: 0)
        q.files.delete(DraftQuarantine.ownerName)
        let geaendert = Date().addingTimeInterval(-91 * tag)
        ordner(q).changedAt = geaendert
        XCTAssertFalse(DraftQuarantine.expired(q.files))
        XCTAssertEqual(DraftQuarantine.staleCount([q]), 2)
        let ende = try XCTUnwrap(DraftQuarantine.finalDeletion([q]))
        XCTAssertEqual(ende.timeIntervalSince1970, geaendert.addingTimeInterval(120 * tag).timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(DraftQuarantine.expired(q.files, now: geaendert.addingTimeInterval(121 * tag)))
        ordner(q).changedAt = Date().addingTimeInterval(-121 * tag)
        XCTAssertTrue(DraftQuarantine.expired(q.files))
    }

    // Erneute Abmeldung desselben Kontos: älteres `since` bleiben

    func testErneuteAbmeldungBehaeltAelteresSeit() throws {
        let q = alteQuarantaene(tage: 100)
        let frueher = try XCTUnwrap(DraftQuarantine.owner(q.files)).since
        let neu = box()
        XCTAssertTrue(neu.seal(Beleg(text: "Noten"), "k-2" + DraftBox.ending))
        XCTAssertEqual(DraftQuarantine.retire(neu, into: q, owner: .init(server: server, email: "E@example.org", since: Date())), 1)
        XCTAssertEqual(try XCTUnwrap(DraftQuarantine.owner(q.files)).since.timeIntervalSince1970, frueher.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(DraftQuarantine.staleCount([q]), 3)
        XCTAssertTrue(DraftQuarantine.expired(q.files, now: frueher.addingTimeInterval(121 * tag)))
    }

    func testErneuteAbmeldungUebernimmtOrdnerdatumOhneKontoDatei() throws {
        let q = alteQuarantaene(tage: 0)
        q.files.delete(DraftQuarantine.ownerName)
        let geaendert = Date().addingTimeInterval(-100 * tag)
        ordner(q).changedAt = geaendert
        let neu = box()
        XCTAssertTrue(neu.seal(Beleg(text: "Noten"), "k-2" + DraftBox.ending))
        DraftQuarantine.retire(neu, into: q, owner: .init(server: server, email: "e@example.org", since: Date()))
        XCTAssertEqual(try XCTUnwrap(DraftQuarantine.owner(q.files)).since.timeIntervalSince1970, geaendert.timeIntervalSince1970, accuracy: 0.001)
    }

    // Entschlüsselte Exportdatei: beim Schließen des Teilens und beim nächsten Start löschen

    func testExportdateiWirdAufgeraeumt() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("quarantaene-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let url = DraftQuarantine.exportURL(in: tmp)
        XCTAssertEqual(url.lastPathComponent, "hubiplan-belege.json")
        try Data("{}".utf8).write(to: url)
        // Datei früherer Fassungen direkt im temporären Verzeichnis
        let alt = tmp.appendingPathComponent("hubiplan-belege.json")
        try Data("{}".utf8).write(to: alt)
        let fremd = tmp.appendingPathComponent("anderes.txt")
        try Data("x".utf8).write(to: fremd)
        DraftQuarantine.clearExports(in: tmp)
        XCTAssertFalse(fm.fileExists(atPath: url.path))
        XCTAssertFalse(fm.fileExists(atPath: alt.path))
        XCTAssertTrue(fm.fileExists(atPath: fremd.path))
        // Nichts da: kein Fehler
        DraftQuarantine.clearExports(in: tmp)
    }

    func testExportLaesstVorgaengeLiegen() throws {
        // Wie Android: nach dem Export bleiben die Vorgänge bis „Löschen“ oder 120 Tage
        let alt = alteQuarantaene(tage: 91)
        _ = try XCTUnwrap(DraftQuarantine.exportStale([alt]))
        XCTAssertEqual(DraftQuarantine.staleCount([alt]), 2)
        XCTAssertNotNil(DraftQuarantine.owner(alt.files))
    }
}
